version 18.0
clear all
set more off

* Run from the credit-default project root:
* do "code/02_logit_table.do"
* Optional arguments: project root, input dataset path.
args project input
if `"`project'"' == "" local project "`c(pwd)'"
* Preparation also runs 00_config.do. Rebuild the common sample each run.
do "`project'/code/01_prepare_data.do" "`project'" "`input'"
use "$CREDIT_DERIVED/analysis_sample.dta", clear
capture log close task1
log using "$CREDIT_LOGS/02_logit_table.log", text replace name(task1)

* Only the requested predictors; no geography or maxed-out exposure.
local spec1 c.age2014 i.female i.low_income
local spec2 `spec1' c.bk_limit_2014m12 c.bk_balance_2014m12
local spec3 `spec2' c.cenco_limit_2014m12 c.cenco_balance_2014m12
local effects1 age2014 female low_income
local effects2 `effects1' bk_limit_2014m12 bk_balance_2014m12
local effects3 `effects2' cenco_limit_2014m12 cenco_balance_2014m12
tempname results
tempfile resultsdata
postfile `results' int model str40 term double estimate se p N default_mean pseudo_r2 using `resultsdata', replace
forvalues m = 1/3 {
    glm def90_target `spec`m'', family(binomial) link(logit) irls
    estimates save "$CREDIT_MODELS/task1_logit`m'.ster", replace
    local N = e(N)
    local ll = -e(deviance)/2
    quietly summarize def90_target if e(sample)
    local mean = 100*r(mean)
    local p0 = r(mean)
    local ll0 = `N'*(`p0'*ln(`p0')+(1-`p0')*ln(1-`p0'))
    local r2 = 1-`ll'/`ll0'
    margins, dydx(`effects`m'')
    matrix M = r(table)
    local names : colnames M
    local k = 0
    foreach term of local names {
        local ++k
        if !inlist("`term'","0b.female","0b.low_income") {
            post `results' (`m') ("`term'") (100*M[1,`k']) (100*M[2,`k']) (M[4,`k']) (`N') (`mean') (`r2')
        }
    }
}
postclose `results'
use `resultsdata', clear
export delimited using "$CREDIT_TABLES/task1_marginal_effects.csv", replace
import delimited "$CREDIT_TABLES/task1_marginal_effects.csv", clear
tempfile stats
* Build seven fixed rows, then model-statistic rows.
generate byte row = .
replace row = 1 if term == "age2014"
replace row = 2 if term == "1.female"
replace row = 3 if term == "1.low_income"
replace row = 4 if term == "bk_limit_2014m12"
replace row = 5 if term == "bk_balance_2014m12"
replace row = 6 if term == "cenco_limit_2014m12"
replace row = 7 if term == "cenco_balance_2014m12"
assert !missing(row)
generate str60 cell = strtrim(string(estimate,"%9.2f"))
replace cell = cell + "***" if p < .01
replace cell = cell + "**" if p >= .01 & p < .05
replace cell = cell + "*" if p >= .05 & p < .10
replace cell = cell + " (" + strtrim(string(se,"%9.2f")) + ")"
preserve
    keep model n default_mean pseudo_r2
    duplicates drop
    expand 3
    bysort model: generate byte row = 7 + _n
    generate str60 cell = strtrim(string(default_mean,"%9.2f")) if row == 8
    replace cell = strtrim(string(n,"%15.0fc")) if row == 9
    replace cell = strtrim(string(pseudo_r2,"%9.3f")) if row == 10
    keep model row cell
    save `stats'
restore
keep model row cell
append using `stats'
reshape wide cell, i(row) j(model)
generate str40 predictor = ""
replace predictor = "Age (10 years)" if row == 1
replace predictor = "Female" if row == 2
replace predictor = "Low income (bracket 1)" if row == 3
replace predictor = "Bank credit limit" if row == 4
replace predictor = "Bank credit balance" if row == 5
replace predictor = "JV NBI credit limit" if row == 6
replace predictor = "JV NBI credit balance" if row == 7
replace predictor = "Default mean (%)" if row == 8
replace predictor = "Observations" if row == 9
replace predictor = "Pseudo R-squared" if row == 10
sort row
drop row
order predictor cell1 cell2 cell3
label variable predictor "Predictor / statistic"
label variable cell1 "(1) Demographics"
label variable cell2 "(2) + Bank information"
label variable cell3 "(3) + JV NBI information"
export delimited using "$CREDIT_TABLES/task1_table.csv", replace
export excel using "$CREDIT_TABLES/task1_table.xlsx", firstrow(varlabels) replace

display "Table reports average marginal effects (percentage points), delta-method SEs."
display "Binary effects compare 1 versus 0. Conventional model-based SEs."
log close task1