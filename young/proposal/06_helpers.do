version 18.0
* Shared routines. Loaded by each proposal script; do not run separately.
global PROP_METRICS "$CREDIT_ROOT/outputs/metrics/proposal"
global PROP_FIGURES "$CREDIT_ROOT/outputs/figures/proposal"
capture mkdir "$CREDIT_ROOT/outputs/metrics"
capture mkdir "$CREDIT_ROOT/outputs/figures"
capture mkdir "$PROP_METRICS"
capture mkdir "$PROP_FIGURES"
global PROP_NAMES "n prevalence auc average_precision log_loss brier recall_fpr05 recall_fpr10 precision_top05 lift_top05 precision_top10 lift_top10"
mata:
real matrix prop_curve(real colvector y, real colvector p)
{
    real matrix z, g
    real colvector cases, controls, tp, fp
    z=sort((-p,y),(1,2))
    g=panelsetup(z,1)
    cases=panelsum(z[,2],g)
    controls=panelsum(1:-z[,2],g)
    tp=runningsum(cases)
    fp=runningsum(controls)
    return((.,0,0,1,0,0) \ (-z[g[,1],1],tp:/sum(cases),fp:/sum(controls),tp:/(tp:+fp),cases,controls))
}
real scalar prop_top(real matrix c, real scalar q)
{
    real colvector size, prior, fraction
    real scalar capacity
    size=c[,5]:+c[,6]
    prior=runningsum(size):-size
    capacity=max((1,floor(q*sum(size))))
    fraction=rowmin((size,rowmax((J(rows(size),1,0),J(rows(size),1,capacity):-prior))))
    fraction=fraction:/(size:+(size:==0))
    return(sum(fraction:*c[,5])/capacity)
}
real rowvector prop_metrics(real colvector y, real colvector p)
{
    real matrix c
    real colvector dr, df, clip
    real scalar n, prev, auc, ap, ll, bs, r05, r10, p05, p10
    n=rows(y); prev=mean(y)
    clip=rowmin((rowmax((p,J(n,1,1e-15))),J(n,1,1-1e-15)))
    ll=-mean(y:*ln(clip)+(1:-y):*ln(1:-clip))
    bs=mean((p-y):^2)
    if (prev==0 | prev==1) return((n,prev,.,.,ll,bs,J(1,6,.)))
    c=prop_curve(y,p)
    dr=c[2..rows(c),2]-c[1..rows(c)-1,2]
    df=c[2..rows(c),3]-c[1..rows(c)-1,3]
    auc=sum(df:*(c[2..rows(c),2]+c[1..rows(c)-1,2]):/2)
    ap=sum(dr:*c[2..rows(c),4])
    r05=max(select(c[,2],c[,3]:<=.05))
    r10=max(select(c[,2],c[,3]:<=.10))
    p05=prop_top(c,.05); p10=prop_top(c,.10)
    return((n,prev,auc,ap,ll,bs,r05,r10,p05,p05/prev,p10,p10/prev))
}
end
capture program drop prop_eval
program define prop_eval, rclass
    version 18.0
    syntax varlist(min=2 max=2 numeric) [if] [in]
    marksample touse
    gettoken outcome prediction : varlist
    quietly count if `touse'
    if r(N)==0 error 2000
    assert inlist(`outcome',0,1) if `touse'
    assert inrange(`prediction',0,1) if `touse'
    mata: st_matrix("__prop_metrics",prop_metrics(st_data(.,"`outcome'","`touse'"),st_data(.,"`prediction'","`touse'")))
    local j=0
    foreach name of global PROP_NAMES {
        local ++j
        return scalar `name'=__prop_metrics[1,`j']
    }
end
capture program drop prop_load_test
program define prop_load_test
    version 18.0
    use "$CREDIT_DERIVED/test_predictions.dta", clear
    isid ind_id
    merge 1:1 ind_id using "$CREDIT_DERIVED/split_assignments.dta"
    assert _merge!=1
    assert train==0 if _merge==3
    assert train==1 if _merge==2
    keep if _merge==3
    drop _merge train
    sort ind_id
    assert inlist(def90_target,0,1)
    assert inlist(young,0,1) & inlist(female,0,1) & inlist(low_income,0,1)
    egen byte missing_inputs=rowmiss(def90_target young female low_income bk_limit_2014m12 bk_balance_2014m12 cenco_limit_2014m12 cenco_balance_2014m12 pd_bank pd_jv)
    assert missing_inputs==0
    drop missing_inputs
    foreach model in bank jv {
        estimates use "$CREDIT_MODELS/task2_logit_`model'.ster"
        quietly predict double restored_prediction, mu
        assert abs(restored_prediction-pd_`model')<1e-10
        drop restored_prediction
    }
end
capture program drop prop_load_analysis
program define prop_load_analysis
    version 18.0
    use "$CREDIT_DERIVED/analysis_sample.dta", clear
    isid ind_id
    merge 1:1 ind_id using "$CREDIT_DERIVED/split_assignments.dta"
    assert _merge==3
    drop _merge
    assert inlist(train,0,1)
    egen byte missing_inputs=rowmiss(def90_target young female low_income bk_limit_2014m12 bk_balance_2014m12 cenco_limit_2014m12 cenco_balance_2014m12)
    assert missing_inputs==0
    drop missing_inputs
    sort ind_id
end
