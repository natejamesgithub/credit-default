version 18.0
clear all
set more off
args project repeats
if `"`project'"' == "" local project "`c(pwd)'/young"
do "`project'/code/00_config.do" "`project'"
do "`project'/proposal/06_helpers.do"
capture log close proposal
log using "$CREDIT_LOGS/06f_paired_bootstrap.log", text replace name(proposal)

if `"`repeats'"'=="" local repeats 200
assert real("`repeats'")>=20 & real("`repeats'")==floor(real("`repeats'"))
prop_load_test
* Ordinary paired borrower bootstrap, conditional on already fitted models.
* The same sampled indices are used for both sets of probabilities.
mata:
y=st_data(.,"def90_target")
pbank=st_data(.,"pd_bank")
pjv=st_data(.,"pd_jv")
basebank=prop_metrics(y,pbank)
basejv=prop_metrics(y,pjv)
st_matrix("bootstrap_point",basejv-basebank)
end
set seed 20261022
tempname results
tempfile resultdata
postfile `results' int repetition str24 metric double difference using `resultdata'
forvalues rep=1/`repeats' {
    mata: sampled=1:+floor(runiform(rows(y),1):*rows(y)); differences=prop_metrics(y[sampled],pjv[sampled])-prop_metrics(y[sampled],pbank[sampled]); st_matrix("bootstrap_difference",differences)
    local j=0
    foreach metric of global PROP_NAMES {
        local ++j
        if !inlist("`metric'","n","prevalence") post `results' (`rep') ("`metric'") (bootstrap_difference[1,`j'])
    }
    if mod(`rep',10)==0 display "Completed bootstrap `rep' of `repeats'"
}
postclose `results'
use `resultdata', clear
save "$PROP_METRICS/bootstrap_repetitions.dta", replace
export delimited using "$PROP_METRICS/bootstrap_repetitions.csv", replace
tempname summary
tempfile summarydata
postfile `summary' str24 metric double point_difference double ci_lower double ci_upper double bootstrap_sd int repetitions using `summarydata'
local j=0
foreach metric of global PROP_NAMES {
    local ++j
    if !inlist("`metric'","n","prevalence") {
        quietly summarize difference if metric=="`metric'"
        local sd=r(sd)
        _pctile difference if metric=="`metric'", p(2.5 97.5)
        post `summary' ("`metric'") (bootstrap_point[1,`j']) (r(r1)) (r(r2)) (`sd') (`repeats')
    }
}
postclose `summary'
use `summarydata', clear
* Positive improvement always means better. Raw difference is JV minus bank.
generate double improvement=point_difference
generate double improvement_ci_lower=ci_lower
generate double improvement_ci_upper=ci_upper
replace improvement=-point_difference if inlist(metric,"log_loss","brier")
replace improvement_ci_lower=-ci_upper if inlist(metric,"log_loss","brier")
replace improvement_ci_upper=-ci_lower if inlist(metric,"log_loss","brier")
export delimited using "$PROP_METRICS/bootstrap_confidence_intervals.csv", replace
display "Percentile intervals condition on fitted models; they do not include retraining uncertainty."

log close proposal
