version 18.0
clear all
set more off
args project 
if `"`project'"' == "" local project "`c(pwd)'/young"
do "`project'/code/00_config.do" "`project'"
do "`project'/proposal/06_helpers.do"
capture log close proposal
log using "$CREDIT_LOGS/06a_performance_calibration.log", text replace name(proposal)

prop_load_test
quietly summarize def90_target
local prevalence=r(mean)
tempname metrics calibration
tempfile metricdata caldata curves bins
postfile `metrics' str8 model str24 metric double value using `metricdata'
postfile `calibration' str8 model double intercept double intercept_se double slope double slope_se long n using `caldata'
local first_curve=1
local first_bins=1
foreach model in bank jv {
    prop_eval def90_target pd_`model'
    foreach metric of global PROP_NAMES {
        post `metrics' ("`model'") ("`metric'") (r(`metric'))
    }
    * Curves use all observations; only rendering coordinates are thinned.
    mata: C=prop_curve(st_data(.,"def90_target"),st_data(.,"pd_`model'")); idx=uniqrows(1:+floor((0::2000):*(rows(C)-1)/2000)); plotC=C[idx,(2,4)]; st_local("curve_n",strofreal(rows(plotC)))
    preserve
        clear
        set obs `curve_n'
        generate double recall=.
        generate double precision=.
        mata: st_store(.,("recall","precision"),plotC)
        generate str8 model="`model'"
        if !`first_curve' append using `curves'
        save `curves', replace
    restore
    local first_curve=0
    preserve
        xtile calibration_bin=pd_`model', nq(10)
        collapse (mean) predicted=pd_`model' observed=def90_target (count) n=def90_target, by(calibration_bin)
        generate str8 model="`model'"
        if !`first_bins' append using `bins'
        save `bins', replace
    restore
    local first_bins=0
    * Native linear score avoids infinite logit(0) or logit(1).
    estimates use "$CREDIT_MODELS/task2_logit_`model'.ster"
    predict double calibration_score, xb
    glm def90_target c.calibration_score, family(binomial) link(logit) irls
    assert e(rc)==0
    post `calibration' ("`model'") (_b[_cons]) (_se[_cons]) (_b[calibration_score]) (_se[calibration_score]) (e(N))
    drop calibration_score
}
postclose `metrics'
postclose `calibration'
use `metricdata', clear
export delimited using "$PROP_METRICS/performance_metrics.csv", replace
reshape wide value, i(metric) j(model) string
rename valuebank bank
rename valuejv bank_jv
generate double change=bank_jv-bank
generate double improvement=change
replace improvement=-change if inlist(metric,"log_loss","brier")
replace improvement=. if inlist(metric,"n","prevalence")
export delimited using "$PROP_METRICS/performance_comparison.csv", replace
use `caldata', clear
export delimited using "$PROP_METRICS/calibration_parameters.csv", replace
use `bins', clear
export delimited using "$PROP_METRICS/calibration_bins.csv", replace
twoway (connected observed predicted if model=="bank",sort msymbol(O) lcolor(navy) mcolor(navy)) (connected observed predicted if model=="jv",sort msymbol(D) lcolor(maroon) mcolor(maroon)) (function y=x,range(0 1) lpattern(dash) lcolor(gs10)), title("Do predicted risks match observed defaults?") xtitle("Mean predicted probability") ytitle("Observed default rate") legend(order(1 "Bank information" 2 "Bank + JV information") rows(1) position(6)) graphregion(color(white)) name(proposal_calibration,replace)
graph save "$PROP_FIGURES/calibration.gph", replace
graph export "$PROP_FIGURES/calibration.png", replace width(1800)
use `curves', clear
export delimited using "$PROP_METRICS/pr_curve_display.csv", replace
twoway (line precision recall if model=="bank",sort lcolor(navy)) (line precision recall if model=="jv",sort lcolor(maroon)), yline(`prevalence',lpattern(dash) lcolor(gs10)) title("Precision-recall on held-out borrowers") xtitle("Recall: share of defaulters detected") ytitle("Precision: default share among flagged borrowers") xlabel(0(.2)1) ylabel(0(.2)1) legend(order(1 "Bank information" 2 "Bank + JV information") rows(1) position(6)) note("Dashed line: test default rate. Average precision uses every test borrower.",size(vsmall)) graphregion(color(white)) name(proposal_pr,replace)
graph save "$PROP_FIGURES/precision_recall.gph", replace
graph export "$PROP_FIGURES/precision_recall.png", replace width(1800)

log close proposal
