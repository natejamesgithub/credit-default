global data "/Users/ahurtado/Dropbox/Research/Projects/FoleyHurtadoSepulveda/1_analysis/data"
global exhibits "/Users/ahurtado/Dropbox/Research/Projects/FoleyHurtadoSepulveda/2_exhibits"
global figures "/Users/ahurtado/Dropbox/Research/Projects/FoleyHurtadoSepulveda/2_exhibits/figures"
global tables "/Users/ahurtado/Dropbox/Research/Projects/FoleyHurtadoSepulveda/2_exhibits/tables"

**********************************************************
* Prediction target: Ever 90+ default from Jan-May 2015 *
***********************************************************
u "$data/master_data", clear

keep if inrange(date,201501,201505)

g def90 = (delinq == 4 | delinq == 5 | delinq == 6)

collapse (max) def90_target=def90, by(ind_id)

lab var def90_target "Prediction target: Dummy = 1 if 90+ default during Jan-May 2015"

tempfile target
sa `target'


**********************************
* Predictors: December 2014 *
**********************************
u "$data/master_data", clear

keep if date == 201412

// CAT admin as retail lender
replace retail = 1 if bank_id == 103

// Bank limit
g bk_limit_2014m12 = limit if retail == 0
replace bk_limit_2014m12 = 0 if bk_limit_2014m12 == .

// Bank balance
g bk_balance_2014m12 = usage if retail == 0
replace bk_balance_2014m12 = 0 if bk_balance_2014m12 == .

// Cencosud limit
g cenco_limit_2014m12 = limit if bank_id == 9
replace cenco_limit_2014m12 = 0 if cenco_limit_2014m12 == .

// Cencosud balance
g cenco_balance_2014m12 = usage if bank_id == 9
replace cenco_balance_2014m12 = 0 if cenco_balance_2014m12 == .

// Maxed-out exposure
g cenco_ut_2014m12 = 100*cenco_balance_2014m12/cenco_limit_2014m12 
g maxed_out = (cenco_ut_2014m12 == 100)
g cenco_mo_exp_2014m12 = cenco_balance_2014m12*maxed_out

collapse ///
	(sum) bk_limit_2014m12 bk_balance_2014m12 ///
	cenco_limit_2014m12 cenco_balance_2014m12 ///
	cenco_mo_exp_2014m12 ///
	(mean) income_bin_sii, ///
	by(ind_id)
	
****************
* Demographics *
****************

merge 1:1 ind_id using "$data/demographics/ind_id_demo.dta"
drop if _merge == 2
drop _merge

g birth_year = year(prs_fec_nacimiento)
g age2014 = 2014 - birth_year

g female = 1 if prs_sexo == 2
replace female = 0 if prs_sexo == 1

***************************
* Keep Cencosud borrowers *
***************************

merge 1:1 ind_id using "$data/cenco_ID.dta"
drop if _merge == 2
drop _merge

keep if cencosud == 1

*************
* Geography *
*************

merge 1:1 ind_id using "$data/geodata/ind_date_comuna_vars2017_2015m5.dta"
keep if _merge == 3
drop _merge

foreach x of varlist comuna_code region_code income_bin_sii female {
	replace `x' = 9999 if `x' == .
}

***********************
* Add prediction target *
***********************

merge 1:1 ind_id using `target'
keep if _merge == 3
drop _merge

***************************
* Final prediction sample *
***************************

keep ind_id def90_target ///
	bk_balance_2014m12 bk_limit_2014m12 ///
	cenco_balance_2014m12 cenco_limit_2014m12 ///
	cenco_mo_exp_2014m12 ///
	age2014 female income_bin_sii region_code comuna_code

duplicates drop
compress

isid ind_id

// Rescaling for interpretation
foreach x of varlist ///
    bk_limit_2014m12 ///
    bk_balance_2014m12 ///
    cenco_limit_2014m12 ///
    cenco_balance_2014m12 ///
    cenco_mo_exp_2014m12 {

    replace `x' = `x'/1000000
}

replace age2014 = age2014/10

duplicates drop
compress
save "$data/predicting default/pre_sample.dta", replace
export delimited "$data/predicting default/pre_sample.csv", replace

********************
* Prediction model *
********************
/// Specifications
local spec1 bk_limit_2014m12 bk_balance_2014m12
local spec2 `spec1' cenco_limit_2014m12 cenco_balance_2014m12
local spec3 `spec2' cenco_mo_exp_2014m12

// Common sample for all six models
tempvar sample
mark `sample'
markout `sample' def90_target `spec3' ///
    age2014 female income_bin_sii region_code comuna_code
	
// Temporary files for the six table columns
tempfile col1 col2 col3 col4 col5 col6
local j = 0

foreach link in logit {
    forvalues s = 1/2 {
        local ++j

        // Information set and link
        glm def90_target ///
            `spec`s'' ///
            age2014 ///
            i.female ///
            ib1.income_bin_sii ///
            i.comuna_code ///
            if `sample', ///
            family(binomial) link(`link') irls

        // Diagnostics
        capture drop pdhat_logit`s'
        predict double pdhat_logit`s' if e(sample), mu

        display "DIAGNOSTICS: model_`s'"
        display "Intercept: " %16.10f _b[_cons]
        display "Female coefficient: " %16.10f _b[1.female]

        quietly summarize def90_target if e(sample)
        local observed = 100*r(mean)

        quietly summarize pdhat_logit`s' if e(sample)
        local predicted = 100*r(mean)

        display "Observed default rate (%): " %16.10f `observed'
        display "Mean PD (%): " %16.10f `predicted'
        display "Difference (percentage points): " ///
            %16.10f (`predicted' - `observed')

        quietly summarize pdhat_logit`s' if ind_id == 4
        display "Borrower 4 PD (%): " %16.10f (100*r(mean))
    }
}

foreach link in logit probit {
    forvalues s = 1/3 {
        local ++j

        // Information set and link
        glm def90_target ///
            `spec`s'' ///
            age2014 ///
            i.female ///
            ib1.income_bin_sii ///
            i.comuna_code ///
            if `sample', ///
            family(binomial) link(`link') irls

        est store pd_`link'`s'

        // Model table
        preserve

            // Save model statistics before margins
            local N = e(N)

            qui sum def90_target if e(sample)
            local p0 = r(mean)
            local def_mean = 100*`p0'

            // Glm, irls does not store e(r2_p).
            // For this binary outcome, log likelihood = -deviance/2.
            local ll = -e(deviance)/2
            local ll0 = `N'*(`p0'*ln(`p0') + ///
                (1-`p0')*ln(1-`p0'))
            local pseudo_r2 = 1 - `ll'/`ll0'

            ********************
            * Marginal effects *
            ********************

            // Variables included in each specification
            margins, dydx( ///
                `spec`s'' ///
                age2014 ///
                female ///
                income_bin_sii) post

            parmest, norestore

            // Convert marginal effects to percentage points
            replace estimate = 100*estimate
            replace stderr = 100*stderr

            // CKey variables
            keep if inlist(parm, ///
                "bk_limit_2014m12", ///
                "bk_balance_2014m12", ///
                "cenco_limit_2014m12", ///
                "cenco_balance_2014m12", ///
                "cenco_mo_exp_2014m12", ///
                "age2014", ///
                "1.female") | ///
                regexm(parm, "^[2-8]\.income_bin_sii$")

            // Row order
            g order = .
            replace order = 1  if parm == "bk_limit_2014m12"
            replace order = 2  if parm == "bk_balance_2014m12"
            replace order = 3  if parm == "cenco_limit_2014m12"
            replace order = 4  if parm == "cenco_balance_2014m12"
            replace order = 5  if parm == "cenco_mo_exp_2014m12"
            replace order = 6  if parm == "age2014"
            replace order = 7  if parm == "1.female"
            replace order = 8  if parm == "2.income_bin_sii"
            replace order = 9  if parm == "3.income_bin_sii"
            replace order = 10 if parm == "4.income_bin_sii"
            replace order = 11 if parm == "5.income_bin_sii"
            replace order = 12 if parm == "6.income_bin_sii"
            replace order = 13 if parm == "7.income_bin_sii"
            replace order = 14 if parm == "8.income_bin_sii"

            // Row labels
            g str40 var = parm

            replace var = "Bank Credit Limit" ///
                if parm == "bk_limit_2014m12"
            replace var = "Bank Credit Balance" ///
                if parm == "bk_balance_2014m12"
            replace var = "JV NBI Credit Limit" ///
                if parm == "cenco_limit_2014m12"
            replace var = "JV NBI Credit Balance" ///
                if parm == "cenco_balance_2014m12"
            replace var = "JV NBI Maxed-Out Exposure" ///
                if parm == "cenco_mo_exp_2014m12"
            replace var = "Age" if parm == "age2014"
            replace var = "Female" if parm == "1.female"

            replace var = "Income Bracket 2" if parm == "2.income_bin_sii"
            replace var = "Income Bracket 3" if parm == "3.income_bin_sii"
            replace var = "Income Bracket 4" if parm == "4.income_bin_sii"
            replace var = "Income Bracket 5" if parm == "5.income_bin_sii"
            replace var = "Income Bracket 6" if parm == "6.income_bin_sii"
            replace var = "Income Bracket 7" if parm == "7.income_bin_sii"
            replace var = "Income Bracket 8" if parm == "8.income_bin_sii"

            ******************
            * Format results *
            ******************

            g str20 Model = string(estimate, "%9.2f")

            replace Model = Model + "***" if p < .01
            replace Model = Model + "**"  if p >= .01 & p < .05
            replace Model = Model + "*"   if p >= .05 & p < .10

            g str20 se = "(" + string(stderr, "%9.2f") + ")"

            *************************
            * Build table structure *
            *************************

            // Create coefficient/SE rows without nested preserve
            expand 2, gen(is_se)
            g row = 2*order - 1 + is_se

            replace Model = se if is_se == 1
            replace var = "" if is_se == 1

            sort row
            keep row var Model

            ************************
            * Add model statistics *
            ************************

            local nrows = _N
            set obs `=`nrows'+3'

            replace var = "Default Mean" if _n == `nrows'+1
            replace Model = string(`def_mean', "%9.2f") ///
                if _n == `nrows'+1

            replace var = "Observations" if _n == `nrows'+2
            replace Model = string(`N', "%15.0fc") ///
                if _n == `nrows'+2

            replace var = "Pseudo R-squared" if _n == `nrows'+3
            replace Model = string(`pseudo_r2', "%9.3f") ///
                if _n == `nrows'+3

            // Fixed statistic rows across all specifications
            replace row = 29 if _n == `nrows'+1
            replace row = 30 if _n == `nrows'+2
            replace row = 31 if _n == `nrows'+3

            // Save this model's column
            ren Model Model`j'
            save `col`j'', replace

        restore
    }
}

****************
* Export table *
****************

preserve
    // Combine all six columns by their fixed row identifiers
    use `col1', clear

    forvalues j = 2/6 {
        merge 1:1 row using `col`j'', nogen
    }

    sort row
    drop row

    lab var Model1 "(1)"
	lab var Model2 "(2)"
	lab var Model3 "(3)"
	lab var Model4 "(4)"
	lab var Model5 "(5)"
	lab var Model6 "(6)"

	texsave var Model1 Model2 Model3 Model4 Model5 Model6 ///
		using "$exhibits/_final/pd_models_pre_post.tex", ///
		location(H) ///
		size(5) ///
		varlabels ///
		headerlines( ///
			"& \multicolumn{3}{c}{Logit Model} & \multicolumn{3}{c}{Probit Model}" ///
			"\cmidrule(lr){2-4} \cmidrule(lr){5-7}") ///
		hlines(-2 -3) ///
		rowsep(.05cm) ///
		frag ///
		nofix ///
		noendash ///
		replace
restore



/*
*******************************
* Change in predicted default *
*******************************

foreach link in logit probit {

    // Predicted probabilities from each specification
    forvalues s = 1/3 {
        est restore pd_`link'`s'
        predict double pdhat_`link'`s' if e(sample), mu
    }

    // Full JV NBI information relative to bank information
    g double delta_pd_`link' = ///
        100*(pdhat_`link'3 - pdhat_`link'1)

    lab var delta_pd_`link' ///
        "Change in predicted default probability (pp): `link'"
}

summarize delta_pd_logit delta_pd_probit, detail

g double delta_pd_logit_limits_balances = ///
    100*(pdhat_logit2 - pdhat_logit1)

g double delta_pd_probit_limits_balances = ///
    100*(pdhat_probit2 - pdhat_probit1)









// Prediction inputs
g pd_limit = bk_limit_2014m12
g pd_balance = bk_balance_2014m12

// Model
glm def90_target ///
	pd_limit ///
	pd_balance ///
	age2014 ///
	i.female ///
	ib1.income_bin_sii ///
	i.region_code ///
	i.comuna_code, ///
	family(binomial) link(logit) irls
	
est store pd_mod

// Model table 
preserve
	// Save model statistics before margins
	local N = e(N)
	local pseudo_r2 = e(r2_p)

	qui sum def90_target if e(sample)
	local def_mean = 100*r(mean)


	********************
	* Marginal effects *
	********************

	margins, dydx( ///
		bk_limit_2014m12 ///
		bk_balance_2014m12 ///
		age2014 ///
		i.female ///
		ib1.income_bin_sii) post

	parmest, norestore

	// Convert marginal effects from probability units to percentage points
	replace estimate = 100*estimate
	replace stderr = 100*stderr

	// Keep marginal effects reported in the table
	keep if inlist(parm, ///
		"bk_limit_2014m12", ///
		"bk_balance_2014m12", ///
		"age2014", ///
		"1.female") | ///
		regexm(parm,"^[2-8]\.income_bin_sii$")


	// Row order
	g order = .
	replace order = 1  if parm == "bk_limit_2014m12"
	replace order = 2  if parm == "bk_balance_2014m12"
	replace order = 3  if parm == "age2014"
	replace order = 4  if parm == "1.female"
	replace order = 5  if parm == "2.income_bin_sii"
	replace order = 6  if parm == "3.income_bin_sii"
	replace order = 7  if parm == "4.income_bin_sii"
	replace order = 8  if parm == "5.income_bin_sii"
	replace order = 9  if parm == "6.income_bin_sii"
	replace order = 10 if parm == "7.income_bin_sii"
	replace order = 11 if parm == "8.income_bin_sii"


	// Row labels
	g str40 var = parm

	replace var = "Bank Credit Limit"   if parm == "bk_limit_2014m12"
	replace var = "Bank Credit Balance" if parm == "bk_balance_2014m12"
	replace var = "Age"                 if parm == "age2014"
	replace var = "Female"              if parm == "1.female"

	replace var = "Income Bracket 2" if parm == "2.income_bin_sii"
	replace var = "Income Bracket 3" if parm == "3.income_bin_sii"
	replace var = "Income Bracket 4" if parm == "4.income_bin_sii"
	replace var = "Income Bracket 5" if parm == "5.income_bin_sii"
	replace var = "Income Bracket 6" if parm == "6.income_bin_sii"
	replace var = "Income Bracket 7" if parm == "7.income_bin_sii"
	replace var = "Income Bracket 8" if parm == "8.income_bin_sii"


	******************
	* Format results *
	******************
	// Estimate and stderr are in percentage points
	g str20 Model = string(estimate,"%9.2f")

	replace Model = Model + "***" if p < .01
	replace Model = Model + "**"  if p >= .01 & p < .05
	replace Model = Model + "*"   if p >= .05 & p < .10

	g str20 se = "(" + string(stderr,"%9.2f") + ")"


	*************************
	* Build table structure *
	*************************

	preserve
		keep var Model order
		g row = 2*order - 1

		tempfile coef
		sa `coef'
	restore

	keep var se order
	ren se Model

	replace var = ""
	g row = 2*order

	append using `coef'

	sort row
	drop order row


	**********************
	* Add model statistics *
	**********************

	local nrows = _N
	set obs `=`nrows'+3'

	replace var = "Default Mean" if _n == `nrows'+1
	replace Model = string(`def_mean',"%9.2f") if _n == `nrows'+1

	replace var = "Observations" if _n == `nrows'+2
	replace Model = string(`N',"%15.0fc") if _n == `nrows'+2

	replace var = "Pseudo R-squared" if _n == `nrows'+3
	replace Model = string(`pseudo_r2',"%9.3f") if _n == `nrows'+3


	****************
	* Export table *
	****************
	lab var Model "(1)"

	texsave var Model using "$exhibits/_final/pd_model_pre.tex", ///
		location(H) ///
		size(4) ///
		varlabels ///
		hlines(-2 -3) ///
		rowsep(.05cm) ///
		frag ///
		nofix ///
		noendash ///
		replace
restore













****************************
* Bank + Cencosud model: g *
****************************
// Prediction inputs
g g_bk_limit = bk_limit_2014m12
g g_bk_balance = bk_balance_2014m12
g g_cenco_limit = cenco_limit_2014m12
g g_cenco_balance = cenco_balance_2014m12

// Estimate g using pre-JV information
glm def90_target ///
	g_bk_limit ///
	g_bk_balance ///
	g_cenco_limit ///
	g_cenco_balance ///
	age2014 ///
	i.female ///
	ib1.income_bin_sii ///
	i.region_code ///
	i.comuna_code, ///
	family(binomial) link(logit) irls
	
est store pd_mod_g

************************
* Predicted default PD *
************************
est restore pd_mod

// December bank PD
predict pd_bank_dec, pr


****************
* May bank PD *
****************

replace pd_limit = bk_limit_2015m5
replace pd_balance = bk_balance_2015m5

predict pd_bank


***************************
* May bank + Cencosud PD *
***************************

replace pd_limit = bk_limit_2015m5 + cenco_limit_2015m5
replace pd_balance = bk_balance_2015m5 + cenco_balance_2015m5

predict pd_bank_cenco, pr


************
* Delta PD *
************

g delta_pd = 100*(pd_bank - pd_bank_cenco)

*****************************
* May bank + Cencosud PD: g *
*****************************

replace g_bk_limit = bk_limit_2015m5
replace g_bk_balance = bk_balance_2015m5
replace g_cenco_limit = cenco_limit_2015m5
replace g_cenco_balance = cenco_balance_2015m5

est restore pd_mod_g

predict pd_bank_cenco_g

***************
* Delta PD, g *
***************
g delta_pd_g = 100*(pd_bank - pd_bank_cenco_g)
sum delta_pd, d

g JV_only = 1 if cenco_limit_2015m5 > 0 & bk_limit_2015m5 == 0
replace JV_only = 0 if cenco_limit_2015m5 > 0 & bk_limit_2015m5 > 0

bys JV_only: sum delta_pd, d

keep if JV_only == 1

merge 1:m ind_id using "$data/incumbent_sample.dta"

/*

// ********************************
// * Credit utilization variables *
// ********************************
//
// // December 2014 bank utilization
// g bk_util_2014m12 = 100*bk_balance_2014m12/bk_limit_2014m12
//
// // May 2015 bank utilization
// g bk_util_2015m5 = 100*bk_balance_2015m5/bk_limit_2015m5
//
// // May 2015 bank + Cencosud limit and balance
// g bk_cenco_limit_2015m5 = bk_limit_2015m5 + cenco_limit_2015m5
// g bk_cenco_balance_2015m5 = bk_balance_2015m5 + cenco_balance_2015m5
//
// // May 2015 bank + Cencosud utilization
// g bk_cenco_util_2015m5 = 100*bk_cenco_balance_2015m5/bk_cenco_limit_2015m5
//
//
// *******************************
// * Maxed-out exposure variables *
// *******************************
//
// // December 2014 bank maxed-out exposure
// g bk_maxed_2014m12 = (bk_util_2014m12 == 100)
// g bk_mo_exp_2014m12 = bk_balance_2014m12*bk_maxed_2014m12
//
// // May 2015 bank maxed-out exposure
// g bk_maxed_2015m5 = (bk_util_2015m5 == 100)
// g bk_mo_exp_2015m5 = bk_balance_2015m5*bk_maxed_2015m5
//
// // May 2015 bank + Cencosud maxed-out exposure
// g bk_cenco_maxed_2015m5 = (bk_cenco_util_2015m5 == 100)
// g bk_cenco_mo_exp_2015m5 = bk_cenco_balance_2015m5*bk_cenco_maxed_2015m5


********************
* Prediction model *
********************

// Rescaling for interpretation
foreach x of varlist ///
	bk_limit_2014m12 ///
	bk_balance_2014m12 ///
	bk_limit_2015m5 ///
	bk_balance_2015m5 ///
	cenco_limit_2015m5 ///
	cenco_balance_2015m5 { ///
	
	replace `x' = `x'/1000000
}
// foreach x of varlist ///
// 	bk_limit_2014m12 ///
// 	bk_balance_2014m12 ///
// 	bk_mo_exp_2014m12 ///
// 	bk_limit_2015m5 ///
// 	bk_balance_2015m5 ///
// 	bk_mo_exp_2015m5 ///
// 	bk_cenco_limit_2015m5 ///
// 	bk_cenco_balance_2015m5 ///
// 	bk_cenco_mo_exp_2015m5 {
//	
// 	replace `x' = `x'/1000000
// }

replace age2014 = age2014/10


// Model 
logit def90_target ///
	bk_limit_2014m12 ///
	bk_balance_2014m12 ///
	age2014 ///
	i.female ///
	i.income_bin_sii ///
	i.region_code ///
	i.comuna_code

// Margins
margins, dydx( ///
	bk_limit_2014m12 ///
	bk_balance_2014m12 ///
	age2014 ///
	i.female ///
	i.income_bin_sii )
	

// // Model 
// logit def90_target ///
// 	bk_limit_2014m12 ///
// 	bk_balance_2014m12 ///
// 	bk_util_2014m12 ///
// 	bk_mo_exp_2014m12 ///
// 	age2014 ///
// 	i.female ///
// 	i.income_bin_sii ///
// 	i.region_code ///
// 	i.comuna_code
//
// // Margins
// margins, dydx( ///
// 	bk_limit_2014m12 ///
// 	bk_balance_2014m12 ///
// 	bk_util_2014m12 ///
// 	bk_mo_exp_2014m12 ///
// 	age2014 ///
// 	i.female i.income_bin_sii )



***************************
* May 2015 bank variables *
***************************

u "$data/master_data", clear

keep if date == 201505

// CAT admin as retail lender
replace retail = 1 if bank_id == 103

// Bank limit
g bk_limit_2015m5 = limit if retail == 0
replace bk_limit_2015m5 = 0 if bk_limit_2015m5 == .

// Bank balance
g bk_balance_2015m5 = usage if retail == 0
replace bk_balance_2015m5 = 0 if bk_balance_2015m5 == .

collapse ///
	(sum) bk_limit_2015m5 bk_balance_2015m5, ///
	by(ind_id)

tempfile may_bank
sa `may_bank'


*****************************
* May 2015 Cencosud variables *
*****************************

u "$data/master_data", clear

keep if date == 201505
keep if bank_id == 103

// Cencosud limit
g cenco_limit_2015m5 = limit
replace cenco_limit_2015m5 = 0 if cenco_limit_2015m5 == .

// Cencosud balance
g cenco_balance_2015m5 = usage
replace cenco_balance_2015m5 = 0 if cenco_balance_2015m5 == .

collapse ///
	(sum) cenco_limit_2015m5 cenco_balance_2015m5, ///
	by(ind_id)

tempfile may_cenco
sa `may_cenco'
