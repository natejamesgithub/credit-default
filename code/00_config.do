version 18.0
set more off

* Pass a project root, or run from the credit-default folder.
args project
if `"`project'"' == "" local project "`c(pwd)'"
global CREDIT_ROOT "`project'"
global CREDIT_RAW "$CREDIT_ROOT/data/raw"
global CREDIT_DERIVED "$CREDIT_ROOT/data/derived"
global CREDIT_TABLES "$CREDIT_ROOT/outputs/tables"
global CREDIT_LOGS "$CREDIT_ROOT/logs"
global CREDIT_MODELS "$CREDIT_ROOT/models"

capture mkdir "$CREDIT_ROOT/data"
capture mkdir "$CREDIT_RAW"
capture mkdir "$CREDIT_DERIVED"
capture mkdir "$CREDIT_ROOT/outputs"
capture mkdir "$CREDIT_TABLES"
capture mkdir "$CREDIT_LOGS"
capture mkdir "$CREDIT_MODELS"