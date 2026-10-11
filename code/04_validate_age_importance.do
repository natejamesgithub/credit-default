version 18.0
clear all
set more off
* Run after task 3; independently validate the first age permutation.
args project
if `"`project'"' == "" local project "`c(pwd)'"
do "`project'/code/00_config.do" "`project'"
capture log close agecheck
log using "$CREDIT_LOGS/04_validate_age_importance.log", text replace name(agecheck)
use "$CREDIT_ROOT/outputs/metrics/task3_permutation_repetitions.dta", clear
keep if predictor == "age2014" & repetition == 1
assert _N == 2
foreach model in bank jv {
    quietly summarize permuted_auc if model == "`model'", meanonly
    local expected_`model' = r(mean)
}
use "$CREDIT_DERIVED/test_predictions.dta", clear
isid ind_id
sort ind_id
clonevar age_original = age2014
quietly count if def90_target == 1
local n1 = r(N)
quietly count if def90_target == 0
local n0 = r(N)
tempname checks
tempfile checkdata
postfile `checks' str8 model double baseline_auc double native_permuted_auc double expected_permuted_auc double age_auc_drop double max_prediction_difference using `checkdata'
foreach model in bank jv {
    replace age2014 = age_original
    sort ind_id
    estimates use "$CREDIT_MODELS/task2_logit_`model'.ster"
    predict double baseline_xb, xb
    * AUC calculated independently using average ranks of probabilities.
    egen double baseline_rank = rank(pd_`model')
    quietly summarize baseline_rank if def90_target == 1, meanonly
    local baseline = (r(sum)-`n1'*(`n1'+1)/2)/(`n1'*`n0')
    drop baseline_rank
    sort ind_id
    set seed 20261012
    mata: original_age=st_data(.,"age_original"); shuffled=order(runiform(rows(original_age),1),1); st_store(.,"age2014",original_age[shuffled])
    * Native prediction after changing the actual predictor in the data.
    predict double native_pd, mu
    generate double algebra_pd = invlogit(baseline_xb + _b[age2014]*(age2014-age_original))
    generate double difference = abs(native_pd-algebra_pd)
    quietly summarize difference, meanonly
    local max_difference = r(max)
    display "Maximum native vs algebra prediction difference: " %21.15g `max_difference'
    assert difference < 1e-12
    egen double prediction_rank = rank(native_pd)
    quietly summarize prediction_rank if def90_target == 1, meanonly
    local shuffled_auc = (r(sum)-`n1'*(`n1'+1)/2)/(`n1'*`n0')
    display "Native AUC: " %21.15g `shuffled_auc' " Expected: " %21.15g `expected_`model''
    assert abs(`shuffled_auc'-`expected_`model'') < 1e-12
    post `checks' ("`model'") (`baseline') (`shuffled_auc') (`expected_`model'') (`baseline'-`shuffled_auc') (`max_difference')
    display "PASS: `model'; native prediction and independent rank AUC match task 3."
    drop baseline_xb native_pd algebra_pd difference prediction_rank
}
postclose `checks'
use `checkdata', clear
export delimited using "$CREDIT_ROOT/outputs/metrics/task3_age_validation.csv", replace
list, noobs
log close agecheck
