version 18.0
clear all
set more off
args project repeats
if `"`project'"' == "" local project "`c(pwd)'/young"
do "`project'/code/00_config.do" "`project'"
do "`project'/proposal/06_helpers.do"
capture log close proposal
log using "$CREDIT_LOGS/06d_grouped_permutation.log", text replace name(proposal)

if `"`repeats'"'=="" local repeats 20
assert real("`repeats'")>=2 & real("`repeats'")==floor(real("`repeats'"))
prop_load_test
local demographics young female low_income
local bank_credit bk_limit_2014m12 bk_balance_2014m12
local jv_credit cenco_limit_2014m12 cenco_balance_2014m12
local all young female low_income bk_limit_2014m12 bk_balance_2014m12 cenco_limit_2014m12 cenco_balance_2014m12
foreach variable of local all {
    clonevar original_`variable'=`variable'
}
tempname results
tempfile resultdata
postfile `results' str8 model str20 group int repetition str24 metric double baseline double permuted double deterioration using `resultdata'
foreach model in bank jv {
    estimates use "$CREDIT_MODELS/task2_logit_`model'.ster"
    prop_eval def90_target pd_`model'
    foreach metric in auc average_precision log_loss brier {
        local baseline_`metric'=r(`metric')
    }
    local groups demographics bank_credit
    if "`model'"=="jv" local groups `groups' jv_credit
    set seed 20261021
    foreach group of local groups {
        forvalues rep=1/`repeats' {
            * One shared permutation preserves relationships within a group.
            mata: shuffled=order(runiform(st_nobs(),1),1)
            foreach variable of local `group' {
                mata: original_values=st_data(.,"original_`variable'"); st_store(.,"`variable'",original_values[shuffled])
            }
            quietly predict double shuffled_pd, mu
            prop_eval def90_target shuffled_pd
            foreach metric in auc average_precision log_loss brier {
                local shuffled_`metric'=r(`metric')
            }
            foreach metric in auc average_precision log_loss brier {
                local drop=`baseline_`metric''-`shuffled_`metric''
                if inlist("`metric'","log_loss","brier") local drop=-`drop'
                post `results' ("`model'") ("`group'") (`rep') ("`metric'") (`baseline_`metric'') (`shuffled_`metric'') (`drop')
            }
            drop shuffled_pd
            foreach variable of local `group' {
                quietly replace `variable'=original_`variable'
            }
        }
        display "Completed `model': `group'"
    }
}
postclose `results'
use `resultdata', clear
save "$PROP_METRICS/grouped_permutation_repetitions.dta", replace
export delimited using "$PROP_METRICS/grouped_permutation_repetitions.csv", replace
collapse (mean) mean_deterioration=deterioration (sd) shuffle_sd=deterioration (count) repeats=deterioration, by(model group metric)
export delimited using "$PROP_METRICS/grouped_permutation_summary.csv", replace
keep if metric=="auc"
generate byte row=.
replace row=1 if group=="jv_credit"
replace row=2 if group=="bank_credit"
replace row=3 if group=="demographics"
generate double position=row+cond(model=="bank",-.17,.17)
twoway (bar mean_deterioration position if model=="bank",horizontal barwidth(.28) color(navy)) (bar mean_deterioration position if model=="jv",horizontal barwidth(.28) color(maroon)), ylabel(1 "JV credit information" 2 "Bank credit information" 3 "Demographics",angle(horizontal)) yscale(reverse) ytitle("") xtitle("Mean test AUC decrease after joint permutation") xline(0,lcolor(gs10)) title("Reliance on groups of borrower information") legend(order(1 "Bank information" 2 "Bank + JV information") rows(1) position(6)) note("Relationships within each group are preserved. Shuffle SD is not a confidence interval.",size(vsmall)) graphregion(color(white)) name(proposal_groups,replace)
graph save "$PROP_FIGURES/grouped_permutation.gph", replace
graph export "$PROP_FIGURES/grouped_permutation.png", replace width(1800)

log close proposal
