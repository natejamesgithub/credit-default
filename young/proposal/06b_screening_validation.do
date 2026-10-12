version 18.0
clear all
set more off
args project 
if `"`project'"' == "" local project "`c(pwd)'/young"
do "`project'/code/00_config.do" "`project'"
do "`project'/proposal/06_helpers.do"
capture log close proposal
log using "$CREDIT_LOGS/06b_screening_validation.log", text replace name(proposal)

* Threshold selection uses only an internal validation part of TRAIN.
* These supplementary models use 80% of the original 70% training sample.
prop_load_analysis
keep if train==1
sort ind_id
set seed 20261020
generate double internal_random=runiform()
sort def90_target internal_random ind_id
by def90_target: generate byte fit_sample=(_n<=floor(.80*_N))
tempname thresholds results
tempfile thresholddata resultdata
postfile `thresholds' str8 model double target_fpr double threshold long fit_n long validation_n using `thresholddata'
postfile `results' str8 model double target_fpr double threshold double actual_test_fpr double test_recall double test_precision long flagged long defaults long n_test using `resultdata'
local bank i.young i.female i.low_income c.bk_limit_2014m12 c.bk_balance_2014m12
local jv `bank' c.cenco_limit_2014m12 c.cenco_balance_2014m12
quietly count if fit_sample==1
local fit_n=r(N)
quietly count if fit_sample==0
local validation_n=r(N)
foreach model in bank jv {
    glm def90_target ``model'' if fit_sample==1, family(binomial) link(logit) irls
    assert e(rc)==0
    estimates save "$CREDIT_MODELS/proposal_screen_`model'.ster", replace
    predict double validation_pd if fit_sample==0, mu
    _pctile validation_pd if fit_sample==0 & def90_target==0, p(90 95)
    local cut10=r(r1)
    local cut05=r(r2)
    foreach target in 05 10 {
        local threshold=`cut`target''
        post `thresholds' ("`model'") (real("`target'")/100) (`threshold') (`fit_n') (`validation_n')
        preserve
            use "$CREDIT_DERIVED/test_predictions.dta", clear
            predict double screen_pd, mu
            generate byte flag=(screen_pd>`threshold')
            quietly count
            local n=r(N)
            quietly count if def90_target==1
            local cases=r(N)
            quietly count if def90_target==0
            local controls=r(N)
            quietly count if flag==1
            local flagged=r(N)
            quietly count if flag==1 & def90_target==1
            local tp=r(N)
            quietly count if flag==1 & def90_target==0
            local fp=r(N)
            local precision=cond(`flagged'>0,`tp'/`flagged',.)
            post `results' ("`model'") (real("`target'")/100) (`threshold') (`fp'/`controls') (`tp'/`cases') (`precision') (`flagged') (`tp') (`n')
        restore
    }
    drop validation_pd
}
postclose `thresholds'
postclose `results'
use `thresholddata', clear
export delimited using "$PROP_METRICS/screening_validation_thresholds.csv", replace
use `resultdata', clear
export delimited using "$PROP_METRICS/screening_test_results.csv", replace
display "Screening models are supplementary: trained on 80% of original training borrowers."
display "Thresholds chosen on internal validation; never optimized on test outcomes."

log close proposal
