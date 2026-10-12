version 18.0
clear all
set more off
args project 
if `"`project'"' == "" local project "`c(pwd)'/young"
do "`project'/code/00_config.do" "`project'"
do "`project'/proposal/06_helpers.do"
capture log close proposal
log using "$CREDIT_LOGS/06e_subgroups.log", text replace name(proposal)

prop_load_test
* Bring age back from the prepared sample; test_predictions does not retain it.
merge 1:1 ind_id using "$CREDIT_DERIVED/analysis_sample.dta", keepusing(age2014) assert(2 3) keep(3) nogen
assert !missing(age2014)
* Age is stored in decades. Rounding avoids float-boundary errors at age 31.
generate int age_years=round(10*age2014)
generate byte age_group=1 if age_years<31
replace age_group=2 if age_years>=31 & age_years<40
replace age_group=3 if age_years>=40 & age_years<50
replace age_group=4 if age_years>=50 & age_years<60
replace age_group=5 if age_years>=60
label define ages 1 "Under 31" 2 "31-39" 3 "40-49" 4 "50-59" 5 "60+"
label values age_group ages
generate byte bank_exposure=(bk_limit_2014m12>0 | bk_balance_2014m12>0)
label define binary_young 0 "Other borrowers" 1 "Young"
label values young binary_young
label define gender 0 "Male" 1 "Female"
label values female gender
label define income 0 "Brackets 2-8" 1 "Bracket 1"
label values low_income income
label define exposure 0 "No bank exposure" 1 "Bank exposure"
label values bank_exposure exposure
tempname results
tempfile resultdata
postfile `results' str20 grouping int level str40 subgroup str8 model str24 metric double value long defaults long nondefaults using `resultdata'
foreach grouping in age_group young female low_income bank_exposure {
    quietly levelsof `grouping', local(levels)
    foreach level of local levels {
        local label : label (`grouping') `level'
        quietly count if `grouping'==`level' & def90_target==1
        local cases=r(N)
        quietly count if `grouping'==`level' & def90_target==0
        local controls=r(N)
        foreach model in bank jv {
            prop_eval def90_target pd_`model' if `grouping'==`level'
            foreach metric of global PROP_NAMES {
                post `results' ("`grouping'") (`level') ("`label'") ("`model'") ("`metric'") (r(`metric')) (`cases') (`controls')
            }
        }
    }
}
postclose `results'
use `resultdata', clear
export delimited using "$PROP_METRICS/subgroup_metrics.csv", replace
reshape wide value, i(grouping level subgroup metric defaults nondefaults) j(model) string
generate double improvement=valuejv-valuebank
replace improvement=-improvement if inlist(metric,"log_loss","brier")
replace improvement=. if inlist(metric,"n","prevalence")
export delimited using "$PROP_METRICS/subgroup_comparison.csv", replace
display "Exploratory subgroup comparisons: no multiple-testing adjustment or subgroup CIs."

log close proposal
