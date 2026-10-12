version 18.0
clear all
set more off
* Run after task 2. Exact interventional SHAP for additive log-odds.
args project
if `"`project'"' == "" local project "`c(pwd)'"
do "`project'/code/00_config.do" "`project'"
global CREDIT_FIGURES "$CREDIT_ROOT/outputs/figures"
global CREDIT_METRICS "$CREDIT_ROOT/outputs/metrics"
capture mkdir "$CREDIT_FIGURES"
capture mkdir "$CREDIT_METRICS"
capture log close task4
log using "$CREDIT_LOGS/05_shap.log", text replace name(task4)
local features young female low_income bk_limit_2014m12 bk_balance_2014m12 cenco_limit_2014m12 cenco_balance_2014m12
use "$CREDIT_DERIVED/analysis_sample.dta", clear
isid ind_id
merge 1:1 ind_id using "$CREDIT_DERIVED/split_assignments.dta"
assert _merge == 3
assert inlist(train,0,1)
drop _merge
foreach variable of local features {
    quietly summarize `variable' if train == 1, meanonly
    local mean_`variable' = r(mean)
}
quietly count if train == 1
local n_train = r(N)
use "$CREDIT_DERIVED/test_predictions.dta", clear
isid ind_id
merge 1:1 ind_id using "$CREDIT_DERIVED/split_assignments.dta"
assert train == 0 if _merge == 3
assert train == 1 if _merge == 2
assert _merge != 1
keep if _merge == 3
drop _merge train
sort ind_id
local n_test = _N
estimates use "$CREDIT_MODELS/task2_logit_jv.ster"
assert e(N) == `n_train'
predict double log_odds, xb
assert abs(invlogit(log_odds)-pd_jv) < 1e-10
scalar reference_log_odds = _b[_cons]
generate double shap_sum = 0
tempname summary
tempfile summarydata
postfile `summary' str40 predictor double training_mean double coefficient double mean_abs_shap using `summarydata'
foreach variable of local features {
    local term "`variable'"
    if inlist("`variable'","female","low_income","young") local term "1.`variable'"
    scalar reference_log_odds = scalar(reference_log_odds)+_b[`term']*`mean_`variable''
    generate double shap_`variable' = _b[`term']*(`variable'-`mean_`variable'')
    replace shap_sum = shap_sum + shap_`variable'
    generate byte high_`variable' = (`variable' >= `mean_`variable'')
    generate double abs_shap = abs(shap_`variable')
    quietly summarize abs_shap, meanonly
    post `summary' ("`variable'") (`mean_`variable'') (_b[`term']) (r(mean))
    drop abs_shap
}
postclose `summary'
generate double shap_reference = scalar(reference_log_odds)
generate double reconstruction_error = abs(shap_reference+shap_sum-log_odds)
assert reconstruction_error < 1e-10
assert abs(invlogit(shap_reference+shap_sum)-pd_jv) < 1e-10
quietly summarize reconstruction_error, meanonly
display "PASS: SHAP contributions reconstruct every test prediction; max log-odds error = " r(max)
char _dta[shap_definition] "Exact interventional SHAP for additive logit score: beta_j*(x_j-training_mean_j); log-odds units"
save "$CREDIT_DERIVED/task4_shap_values.dta", replace
* Global importance uses every test borrower. Display dots use a sample.
set seed 20261013
generate double display_random = runiform()
sort display_random ind_id
keep in 1/4000
local n_display = _N
keep ind_id shap_* high_*
drop shap_sum shap_reference
reshape long shap_ high_, i(ind_id) j(predictor) string
rename shap_ shap_value
rename high_ high_value
tempfile dots
save `dots'
use `summarydata', clear
gsort -mean_abs_shap predictor
generate byte rank = _n
save "$CREDIT_METRICS/task4_shap_summary.dta", replace
export delimited using "$CREDIT_METRICS/task4_shap_summary.csv", replace
keep predictor rank
merge 1:m predictor using `dots'
assert _merge == 3
drop _merge
sort rank ind_id
set seed 20261014
generate double position = rank + .44*(runiform()-.5)
generate str30 label = predictor
replace label = "Young" if predictor == "young"
replace label = "Female" if predictor == "female"
replace label = "Low income" if predictor == "low_income"
replace label = "Bank limit" if predictor == "bk_limit_2014m12"
replace label = "Bank balance" if predictor == "bk_balance_2014m12"
replace label = "JV NBI limit" if predictor == "cenco_limit_2014m12"
replace label = "JV NBI balance" if predictor == "cenco_balance_2014m12"
local axis_labels
forvalues k = 1/7 {
    quietly levelsof label if rank == `k', local(text) clean
    local axis_labels `axis_labels' `k' "`text'"
}
quietly count if !inrange(shap_value,-3,3)
local outside = r(N)
foreach view in full central {
    local restriction ""
    local suffix "_full"
    local subtitle "`n_display' held-out borrowers shown"
    local note "Right: higher risk. Left: lower risk. Rows ranked using all test borrowers."
    if "`view'" == "central" {
        local restriction "& inrange(shap_value,-3,3)"
        local suffix ""
        local subtitle "`n_display' test borrowers sampled; central SHAP range shown"
        local note "`outside' extreme dots omitted here; full-range plot saved separately. Rows ranked using all test borrowers."
    }
    twoway (scatter position shap_value if high_value == 0 `restriction', mcolor(navy%35) msymbol(O) msize(vtiny)) ///
        (scatter position shap_value if high_value == 1 `restriction', mcolor(maroon%35) msymbol(O) msize(vtiny)), ///
        ylabel(`axis_labels', angle(horizontal) noticks) yscale(reverse) ytitle("") ///
        xline(0,lcolor(gs8) lpattern(dash)) xtitle("SHAP contribution to predicted log-odds of default") ///
        title("How predictors change individual default risk") subtitle("`subtitle'") ///
        legend(order(1 "Below training mean" 2 "At or above training mean") rows(1) position(6) size(small)) ///
        note("`note'", size(vsmall)) graphregion(color(white)) name(task4_shap`suffix',replace)
    graph save "$CREDIT_FIGURES/task4_shap`suffix'.gph", replace
    graph export "$CREDIT_FIGURES/task4_shap`suffix'.png", replace width(1800)
}
log close task4