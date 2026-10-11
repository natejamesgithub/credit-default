# Proposal: Additional Evaluation of Default-Prediction Improvement

## Objective

Determine whether adding JV NBI information improves default prediction
beyond ROC AUC, and identify which information contributes to that improvement.

Compare the bank-information model with the bank + JV information model
using the existing 70/30 split and identical test borrowers.

## 1. Additional Performance Metrics

| Metric | What it measures | Evidence of improvement |
|---|---|---|
| Precision–recall AUC / average precision | How effectively the model identifies defaults when defaults are relatively uncommon | Higher values |
| Log loss | Accuracy of predicted probabilities, with strong penalties for confident mistakes | Lower values |
| Brier score | Mean squared difference between predicted probabilities and observed defaults | Lower values |
| Calibration intercept and slope | Whether predicted default probabilities match observed outcomes | Intercept nearer 0; slope nearer 1 |
| Recall at a fixed false-positive rate | Share of defaulters detected while holding false alarms constant | Higher recall |
| Precision and lift in the highest-risk group | Concentration of actual defaults among borrowers ranked riskiest | Higher precision and lift |

### Interpretation

The test default rate is approximately 6.13%. Precision–recall measures
therefore complement ROC AUC by focusing attention on default detection.

Report the precise precision–recall measure used. Average precision and
trapezoidal PR AUC are different calculations and should not be labeled
interchangeably.

Log loss and Brier score evaluate probability quality. A model can improve
risk ranking without improving the accuracy of its probability estimates.

Assess calibration with a reliability plot and calibration intercept/slope.
For the intercept/slope assessment, regress the observed default outcome
on the logit of predicted probability; ideal values are 0 and 1.

For operational comparisons, report recall at selected false-positive rates,
such as 5% and 10%, and precision/lift among the highest-risk 5% and 10%.
Lift equals the selected group's default rate divided by the overall
test default rate.

Any threshold intended for deployment should be chosen using training-side
validation, then evaluated once on the test sample.

## 2. Identify What Drives Improvement

### A. JV information ablation

Fit the following models on the same training borrowers:

1. Demographics + bank limit and balance.
2. Model 1 + JV NBI limit.
3. Model 1 + JV NBI balance.
4. Model 1 + both JV NBI variables.

Evaluate all four on the same test borrowers using ROC AUC,
average precision, log loss, and Brier score.

This identifies the incremental value of each JV variable and their
combined value. Individual gains need not add to the combined gain.

### B. Grouped permutation importance

Extend the existing permutation analysis by jointly shuffling:

- JV NBI limit and balance.
- Bank limit and balance.
- Demographic variables.

Use the same shuffled borrower ordering for every variable within a group
to preserve relationships among the grouped variables.

Measure the resulting loss in AUC and average precision, and the increase
in log loss and Brier score.

This complements individual permutation importance because limits and
balances are related. Joint shuffling preserves their within-group
relationship, although it still breaks relationships with other groups.

### C. Subgroup evaluation

Compare improvements across:

- Age groups.
- Gender.
- Low-income status.
- Borrowers with and without bank credit exposure.

Report subgroup sample sizes, default counts, and default rates alongside
performance metrics.

This can show whether the aggregate improvement is broadly shared or
concentrated among particular borrowers. Interpret precision–recall results
in light of differences in subgroup default prevalence.

## 3. Quantify Uncertainty

Use a paired bootstrap of test borrowers:

- Resample the same borrowers for both models.
- Calculate the difference in each metric for every bootstrap sample.
- Report the estimated improvement and its 95% confidence interval.

This measures test-sample uncertainty conditional on the fitted models.
Repeated training/test splits or cross-validation would additionally assess
sensitivity to model fitting and split selection.

## 4. Recommended Outputs

1. A comparison table covering ROC AUC, average precision, log loss,
   Brier score, and calibration.
2. Precision–recall curves and calibration plots.
3. An ablation table showing the incremental contribution of JV limits
   and balances.
4. A grouped permutation-importance plot.
5. A subgroup comparison table.
6. Paired-bootstrap confidence intervals for performance differences.

## Implementation

Create `code/06_performance_metrics.do`.

The initial metric comparisons can use:

- `data/derived/test_predictions.dta`
- `models/task2_logit_bank.ster`
- `models/task2_logit_jv.ster`

Ablation and grouped permutation analyses also require:

- `data/derived/analysis_sample.dta`
- `data/derived/split_assignments.dta`

Retain the existing split and preprocessing. Fit additional models only on
training borrowers. Save numerical results, figures, and an execution log.

## Priority

Begin with average precision, log loss, Brier score, and calibration.
Then perform JV-variable ablation and grouped permutation importance.

The performance metrics establish whether improvement extends beyond
ranking. Ablation and permutation analyses identify which information
the improvement depends on; they do not establish causal effects.