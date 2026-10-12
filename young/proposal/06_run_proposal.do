version 18.0
clear all
set more off
* Run from original credit-default root. Optional args: parent, bootstrap repeats, permutation repeats.
args parent bootstrap_repeats permutation_repeats
if `"`parent'"'=="" local parent "`c(pwd)'"
if `"`bootstrap_repeats'"'=="" local bootstrap_repeats 200
if `"`permutation_repeats'"'=="" local permutation_repeats 20
local project "`parent'/young"
do "`project'/proposal/06a_performance_calibration.do" "`project'"
do "`project'/proposal/06b_screening_validation.do" "`project'"
do "`project'/proposal/06c_jv_ablation.do" "`project'"
do "`project'/proposal/06d_grouped_permutation.do" "`project'" `permutation_repeats'
do "`project'/proposal/06e_subgroups.do" "`project'"
do "`project'/proposal/06f_paired_bootstrap.do" "`project'" `bootstrap_repeats'
