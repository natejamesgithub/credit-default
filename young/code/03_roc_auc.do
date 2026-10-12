version 18.0
clear all
set more off

* Run from credit-default: do "code/03_roc_auc.do"
* Optional arguments: project root, raw dataset path (if preparation needed).
args project input
if `"`project'"' == "" local project "`c(pwd)'"
do "`project'/code/00_config.do" "`project'"
capture confirm file "$CREDIT_DERIVED/analysis_sample.dta"
if _rc {
    do "`project'/code/01_prepare_data.do" "`project'" "`input'"
}
global CREDIT_FIGURES "$CREDIT_ROOT/outputs/figures"
global CREDIT_METRICS "$CREDIT_ROOT/outputs/metrics"
capture mkdir "$CREDIT_FIGURES"
capture mkdir "$CREDIT_METRICS"
capture log close task2
log using "$CREDIT_LOGS/03_roc_auc.log", text replace name(task2)
use "$CREDIT_DERIVED/analysis_sample.dta", clear
isid ind_id
local allvars young female low_income bk_limit_2014m12 bk_balance_2014m12 cenco_limit_2014m12 cenco_balance_2014m12
egen byte n_missing = rowmiss(def90_target `allvars')
assert n_missing == 0
drop n_missing
assert inlist(def90_target,0,1)
assert inlist(female,0,1) & inlist(low_income,0,1)

* Generate once, then reuse. Stratify by the binary outcome.
* Fixed seed and ID ordering make a new split reproducible.
capture confirm file "$CREDIT_DERIVED/split_assignments.dta"
if _rc {
    sort ind_id
    set seed 20261011
    generate double random_order = runiform()
    sort def90_target random_order ind_id
    by def90_target: generate byte train = (_n <= floor(.70*_N))
    drop random_order
    label define train_label 0 "Test (30%)" 1 "Train (70%)"
    label values train train_label
    preserve
        keep ind_id train
        sort ind_id
        char _dta[split_method] "70/30 stratified by def90_target; seed 20261011"
        save "$CREDIT_DERIVED/split_assignments.dta", replace
    restore
}
else {
    merge 1:1 ind_id using "$CREDIT_DERIVED/split_assignments.dta"
    assert _merge == 3
    drop _merge
}
assert inlist(train,0,1)
tabulate def90_target train, column
forvalues d = 0/1 {
    quietly count if def90_target == `d'
    local n_class = r(N)
    quietly count if def90_target == `d' & train == 1
    assert r(N) == floor(.70*`n_class')
}
quietly count if train == 1
local n_train = r(N)
quietly count if train == 0
local n_test = r(N)
display "Training borrowers: `n_train'; test borrowers: `n_test'"

* Same predictors as task 1 columns 2 and 3, newly fitted on TRAIN ONLY.
local bank i.young i.female i.low_income c.bk_limit_2014m12 c.bk_balance_2014m12
local jv `bank' c.cenco_limit_2014m12 c.cenco_balance_2014m12
foreach model in bank jv {
    glm def90_target ``model'' if train == 1, family(binomial) link(logit) irls
    assert e(N) == `n_train'
    estimates save "$CREDIT_MODELS/task2_logit_`model'.ster", replace
    predict double pd_`model' if train == 0, mu
    assert inrange(pd_`model',0,1) if train == 0
    assert missing(pd_`model') if train == 1
}
preserve
    keep if train == 0
    keep ind_id def90_target `allvars' pd_bank pd_jv
    sort ind_id
    save "$CREDIT_DERIVED/test_predictions.dta", replace
restore

* Exact empirical AUC from all test predictions, with ties receiving
* half credit. This avoids quadratic pairwise comparisons in roctab.
keep if train == 0
quietly count if def90_target == 1
local n_cases = r(N)
quietly count if def90_target == 0
local n_controls = r(N)
assert `n_cases' > 1 & `n_controls' > 1
tempname auc_results
tempfile auc_data bank_curve jv_curve
postfile `auc_results' str30 model double auc long n_train n_test using `auc_data'
foreach model in bank jv {
    preserve
        generate long cases = def90_target
        generate long controls = 1-def90_target
        collapse (sum) cases controls, by(pd_`model')
        sort pd_`model'
        generate double controls_below = sum(controls)-controls
        generate double contribution = cases*(controls_below + .5*controls)
        quietly summarize contribution, meanonly
        local auc_`model' = r(sum)/(`n_cases'*`n_controls')
        assert inrange(`auc_`model'', 0, 1)
        post `auc_results' ("`model'") (`auc_`model'') (`n_train') (`n_test')
        * Curve: count borrowers above each descending score threshold.
        gsort -pd_`model'
        generate double tpr = sum(cases)/`n_cases'
        generate double fpr = sum(controls)/`n_controls'
        rename pd_`model' threshold
        keep threshold tpr fpr
        local extra = _N + 1
        set obs `extra'
        replace tpr = 0 in `extra'
        replace fpr = 0 in `extra'
        generate str8 model = "`model'"
        sort fpr tpr
        save ``model'_curve', replace
    restore
}
postclose `auc_results'
use `bank_curve', clear
append using `jv_curve'
sort model fpr tpr
save "$CREDIT_DERIVED/task2_roc_points.dta", replace
* Render at most about 2,000 points per curve, keeping both endpoints.
* All observations are used for AUC and saved full ROC coordinates.
by model: generate long display_step = max(1,ceil(_N/2000))
by model: keep if _n == 1 | _n == _N | mod(_n,display_step) == 0
local bank_label : display %5.3f `auc_bank'
local jv_label : display %5.3f `auc_jv'
local gain : display %5.3f (`auc_jv'-`auc_bank')
twoway (line tpr fpr if model == "bank", sort lcolor(navy) lwidth(medthick)) ///
    (line tpr fpr if model == "jv", sort lcolor(maroon) lwidth(medthick)) ///
    (function y=x, range(0 1) lcolor(gs10) lpattern(dash)), ///
    title("New information improves default prediction") ///
    subtitle("70% training / 30% testing; stratified random split") ///
    xtitle("False positive rate") ytitle("True positive rate") ///
    xlabel(0(.2)1) ylabel(0(.2)1, angle(horizontal)) ///
    legend(order(1 "Bank information: AUC = `bank_label'" ///
        2 "Bank + JV information: AUC = `jv_label'") rows(2) size(small)) ///
    note("Test-sample AUC improvement: `gain'. Models use task 1 specifications.", size(small)) ///
    graphregion(color(white)) name(task2_roc, replace)
graph save "$CREDIT_FIGURES/task2_roc.gph", replace
graph export "$CREDIT_FIGURES/task2_roc.png", replace width(1800)
use `auc_data', clear
generate double auc_gain = `auc_jv'-`auc_bank'
export delimited using "$CREDIT_METRICS/task2_auc.csv", replace
display "Test AUC: bank = `bank_label'; bank + JV = `jv_label'; gain = `gain'"
log close task2