version 18.0
clear all
set more off
args project 
if `"`project'"' == "" local project "`c(pwd)'/young"
do "`project'/code/00_config.do" "`project'"
do "`project'/proposal/06_helpers.do"
capture log close proposal
log using "$CREDIT_LOGS/06c_jv_ablation.log", text replace name(proposal)

prop_load_analysis
local bank i.young i.female i.low_income c.bk_limit_2014m12 c.bk_balance_2014m12
local limit `bank' c.cenco_limit_2014m12
local balance `bank' c.cenco_balance_2014m12
foreach model in limit balance {
    glm def90_target ``model'' if train==1, family(binomial) link(logit) irls
    assert e(rc)==0
    estimates save "$CREDIT_MODELS/proposal_ablation_`model'.ster", replace
}
prop_load_test
foreach model in limit balance {
    estimates use "$CREDIT_MODELS/proposal_ablation_`model'.ster"
    predict double pd_`model', mu
}
preserve
    keep ind_id def90_target pd_bank pd_limit pd_balance pd_jv
    save "$CREDIT_DERIVED/proposal_ablation_predictions.dta", replace
restore
tempname results
tempfile resultdata
postfile `results' str12 model str24 metric double value using `resultdata'
foreach model in bank limit balance jv {
    prop_eval def90_target pd_`model'
    foreach metric of global PROP_NAMES {
        post `results' ("`model'") ("`metric'") (r(`metric'))
    }
}
postclose `results'
use `resultdata', clear
export delimited using "$PROP_METRICS/jv_ablation_metrics.csv", replace
reshape wide value, i(metric) j(model) string
foreach model in limit balance jv {
    generate double gain_`model'=value`model'-valuebank
    replace gain_`model'=-gain_`model' if inlist(metric,"log_loss","brier")
    replace gain_`model'=. if inlist(metric,"n","prevalence")
}
export delimited using "$PROP_METRICS/jv_ablation_comparison.csv", replace

log close proposal
