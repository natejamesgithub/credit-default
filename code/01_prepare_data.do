version 18.0
clear all
set more off

* Optional arguments: project root, input dataset path.
args project input
if `"`project'"' == "" local project "`c(pwd)'"
do "`project'/code/00_config.do" "`project'"
if `"`input'"' == "" local input "$CREDIT_RAW/pre_sample.dta"
confirm file "`input'"
capture log close preparation
log using "$CREDIT_LOGS/01_prepare_data.log", text replace name(preparation)

use "`input'", clear
isid ind_id
assert inlist(def90_target, 0, 1)
assert inrange(income_bin_sii, 1, 8) | income_bin_sii == 9999 | missing(income_bin_sii)
assert inlist(female, 0, 1, 9999) | missing(female)
local initial_N = _N
count if income_bin_sii == 9999
count if female == 9999

* Original preparation already scaled age in decades and credit in
* millions of CLP. Do not rescale the supplied pre_sample.dta.
generate byte low_income = (income_bin_sii == 1) if inrange(income_bin_sii, 1, 8)
label variable low_income "Low income: bracket 1 vs brackets 2-8"
replace female = . if female == 9999
local allvars age2014 female low_income bk_limit_2014m12 bk_balance_2014m12 cenco_limit_2014m12 cenco_balance_2014m12
egen byte n_missing = rowmiss(def90_target `allvars')
keep if n_missing == 0
drop n_missing
assert _N > 0
isid ind_id
assert inlist(low_income, 0, 1)
assert inlist(female, 0, 1)
label variable age2014 "Age (10 years)"
label variable bk_limit_2014m12 "Bank credit limit (million CLP)"
label variable bk_balance_2014m12 "Bank credit balance (million CLP)"
label variable cenco_limit_2014m12 "JV NBI credit limit (million CLP)"
label variable cenco_balance_2014m12 "JV NBI credit balance (million CLP)"
display "Original N: `initial_N'; common analysis N: " _N
display "Excluded observations: " `initial_N' - _N
tabulate def90_target
save "$CREDIT_DERIVED/analysis_sample.dta", replace
* Task 1 uses the full common sample; no train/test split yet.
log close preparation