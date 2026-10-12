import delimited using "/Users/nate/PROJECTS/RESEARCH/credit-default/young/outputs/metrics/proposal/calibration_bins.csv", clear

twoway ///
    (connected observed predicted if model=="bank", sort ///
        msymbol(O) lcolor(navy) mcolor(navy)) ///
    (connected observed predicted if model=="jv", sort ///
        msymbol(D) lcolor(maroon) mcolor(maroon)) ///
    (function y=x, range(0 .25) lpattern(dash) lcolor(gs10)), ///
    xscale(range(0 .25)) yscale(range(0 .25)) ///
    xlabel(0 "0%" .05 "5%" .10 "10%" .15 "15%" .20 "20%" .25 "25%") ///
    ylabel(0 "0%" .05 "5%" .10 "10%" .15 "15%" .20 "20%" .25 "25%", angle(horizontal)) ///
    title("Do predicted risks match observed defaults?") ///
    xtitle("Mean predicted default probability") ///
    ytitle("Observed default rate") ///
    legend(order(1 "Bank information" 2 "Bank + JV information") ///
        rows(1) position(6)) ///
    graphregion(color(white)) ///
    name(proposal_calibration, replace)

graph save "/Users/nate/PROJECTS/RESEARCH/credit-default/young/outputs/figures/proposal/calibration.gph", replace
graph export "/Users/nate/PROJECTS/RESEARCH/credit-default/young/outputs/figures/proposal/calibration.png", replace width(1800)