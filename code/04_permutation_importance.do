version 18.0
clear all
set more off
* Run after task 2 from credit-default:
* do "code/04_permutation_importance.do"
* Optional arguments: project root, number of permutations (default 20).
args project repeats
if `"`project'"' == "" local project "`c(pwd)'"
if `"`repeats'"' == "" local repeats 20
assert real("`repeats'") >= 2 & real("`repeats'") == floor(real("`repeats'"))
do "`project'/code/00_config.do" "`project'"
global CREDIT_FIGURES "$CREDIT_ROOT/outputs/figures"
global CREDIT_METRICS "$CREDIT_ROOT/outputs/metrics"
capture mkdir "$CREDIT_FIGURES"
capture mkdir "$CREDIT_METRICS"
confirm file "$CREDIT_DERIVED/test_predictions.dta"
confirm file "$CREDIT_DERIVED/split_assignments.dta"
confirm file "$CREDIT_MODELS/task2_logit_bank.ster"
confirm file "$CREDIT_MODELS/task2_logit_jv.ster"
capture log close task3
log using "$CREDIT_LOGS/04_permutation_importance.log", text replace name(task3)
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
local bank age2014 female low_income bk_limit_2014m12 bk_balance_2014m12
local jv `bank' cenco_limit_2014m12 cenco_balance_2014m12
egen byte missing_count = rowmiss(def90_target `jv' pd_bank pd_jv)
assert missing_count == 0
drop missing_count

* Exact rank-based AUC, including ties, in O(N log N).
* Use native predicted probabilities to preserve numerical ties.
mata:
real scalar credit_auc(real colvector y, real colvector score)
{
    real matrix sorted, groups
    real colvector cases, controls, below
    sorted = sort((score,y), (1,2))
    groups = panelsetup(sorted,1)
    cases = panelsum(sorted[,2],groups)
    controls = panelsum(1:-sorted[,2],groups)
    below = runningsum(controls):-controls
    return(sum(cases:*(below:+.5:*controls))/(sum(cases)*sum(controls)))
}
end

tempname results
tempfile repetitions
postfile `results' str8 model str40 predictor int repetition double baseline_auc double permuted_auc double importance using `repetitions', replace
foreach model in bank jv {
    estimates use "$CREDIT_MODELS/task2_logit_`model'.ster"
    predict double original_score, xb
    assert abs(invlogit(original_score)-pd_`model') < 1e-10
    mata: y=st_data(.,"def90_target"); base=st_data(.,"pd_`model'")
    mata: st_numscalar("baseline",credit_auc(y,base))
    display "Model: `model'; baseline test AUC: " scalar(baseline)
    * The same shuffles are used for shared predictors across both models.
    set seed 20261012
    foreach variable of local `model' {
        mata: x=st_data(.,"`variable'")
        forvalues rep = 1/`repeats' {
            * Permute across all test borrowers, not within outcome groups.
            * Keep every other predictor and the fitted model unchanged.
            mata: shuffled=order(runiform(rows(y),1),1)
            mata: st_store(.,"`variable'",x[shuffled])
            quietly predict double shuffled_pd, mu
            mata: st_numscalar("shuffled_auc",credit_auc(y,st_data(.,"shuffled_pd")))
            drop shuffled_pd
            post `results' ("`model'") ("`variable'") (`rep') (scalar(baseline)) (scalar(shuffled_auc)) (scalar(baseline)-scalar(shuffled_auc))
        }
        mata: st_store(.,"`variable'",x)
        display "Completed `model': `variable' (`repeats' shuffles)"
    }
    drop original_score
}
postclose `results'
use `repetitions', clear
save "$CREDIT_METRICS/task3_permutation_repetitions.dta", replace
export delimited using "$CREDIT_METRICS/task3_permutation_repetitions.csv", replace
collapse (mean) mean_drop=importance baseline_auc (sd) sd_drop=importance (count) repeats=importance, by(model predictor)
generate long n_test = `n_test'
export delimited using "$CREDIT_METRICS/task3_permutation_summary.csv", replace

* Display rows in the order used on slide 28, with readable labels.
generate byte row = .
replace row = 1 if predictor == "cenco_limit_2014m12"
replace row = 2 if predictor == "cenco_balance_2014m12"
replace row = 3 if predictor == "bk_limit_2014m12"
replace row = 4 if predictor == "bk_balance_2014m12"
replace row = 5 if predictor == "age2014"
replace row = 6 if predictor == "female"
replace row = 7 if predictor == "low_income"
generate double position = row + cond(model == "bank",-.17,.17)
label define factor_label 1 "JV NBI limit" 2 "JV NBI balance" 3 "Bank limit" 4 "Bank balance" 5 "Age" 6 "Female" 7 "Low income"
label values position factor_label
twoway (bar mean_drop position if model == "bank", horizontal barwidth(.28) color(navy)) ///
    (bar mean_drop position if model == "jv", horizontal barwidth(.28) color(maroon)), ///
    ylabel(1 "JV NBI limit" 2 "JV NBI balance" 3 "Bank limit" 4 "Bank balance" 5 "Age" 6 "Female" 7 "Low income", angle(horizontal) noticks) ///
    yscale(reverse) ytitle("") xtitle("Mean decrease in test AUC after permutation") ///
    xline(0,lcolor(gs10)) xlabel(,format(%5.3f)) ///
    title("What drives default prediction?") ///
    subtitle("70% training / 30% testing; `repeats' permutations per predictor") ///
    legend(order(1 "Bank information" 2 "Bank + JV information") rows(1) size(small) position(6)) ///
    note("Same models and test borrowers as task 2. Absent bars indicate predictors excluded from that model.", size(vsmall)) ///
    graphregion(color(white)) name(task3_permutation,replace)
graph save "$CREDIT_FIGURES/task3_permutation.gph", replace
graph export "$CREDIT_FIGURES/task3_permutation.png", replace width(1800)
display "Importance = baseline AUC minus shuffled AUC; models are never refitted."
log close task3