version 18.0
clear all
set more off
* Run from the ORIGINAL credit-default project root.
args parent input
if `"`parent'"' == "" local parent "`c(pwd)'"
local project "`parent'/young"
do "`project'/code/02_logit_table.do" "`project'" "`input'"
do "`project'/code/03_roc_auc.do" "`project'"
do "`project'/code/04_permutation_importance.do" "`project'"
do "`project'/code/05_shap.do" "`project'"