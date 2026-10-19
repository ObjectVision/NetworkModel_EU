set pf="Program Files"
set config=D:\ProjDir\NetworkModel_EU_FRA_development\cfg
set geodmsversion=GeoDMS20.3.0.c

set countrylist=AT BE BG CH DK ES EE EL CY CZ DE FR FI HR HU IE IT LI LT LU LV MT NL NO RO PL PT SE SI SK

for %%c in (%countrylist%) do (
	
	echo %%c

	rem C:\%pf%\ObjectVision\%geodmsversion%\GeoDmsRun.exe %config%\main.dms /Analyses/Create_Catchments/get_catchments_m10_d/Country_Catchments/%%c/store_catchment

	C:\%pf%\ObjectVision\%geodmsversion%\GeoDmsRun.exe %config%\main.dms /Analyses/Functional_Rural_Areas/gen_eu_dom_10m/iterate_by_Memberstates/%%c/ResultsByVariant/button/runAll

)