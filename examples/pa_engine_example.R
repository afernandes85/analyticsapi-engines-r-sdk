library(factset.analyticsapi.engines)
library(factset.protobuf.stach)
library(httr)

username <- "<username-serial>"
password <- "<apikey>"
url <- "https://api.factset.com"

pa_document <- "PA_DOCUMENTS:DEFAULT"
pa_account1 <- PAIdentifier$new(id = "BENCH:SP50")
pa_account2 <- PAIdentifier$new(id = "BENCH:R.2000")
pa_benchmark1 <- PAIdentifier$new(id = "BENCH:R.1000")
pa_dates <- PADateParameters$new(startdate = "20180101", enddate = "20181231", frequency = "Monthly")
pa_component_name = "Weights"
pa_component_category = "Weights / Exposures"

apiClient <- ApiClient$new(basePath = url, username = username, password = password)

componentsApi <- ComponentsApi$new(apiClient = apiClient)

main <- function (){
  # Build PA Calculation Parameters List ----------------
  components <- tryCatch(
    componentsApi$GetPAComponents(document = pa_document),
    ApiException = function(ex) ex
  )
  if(!is.null(components$ApiException)){
    cat(components$ApiException$toString())
    stop("Api exception encountered")
  }

  componentId <- ""

  for (id in names(components)) {
    if(components[[id]]$name == pa_component_name && components[[id]]$category == pa_component_category) {
      componentId <- id
      break
    }
  }

  if(componentId == "") {
    print(paste("Component Id not found for Component Name", pa_component_name, "and Component Category", pa_component_category))
    stop("Invalid Component Id Error")
  }

  print(paste("PA Component Id:", componentId))

  paCalculations <- list(
    "1" = PACalculationParameters$new(
      componentid = componentId,
      accounts = list(pa_account1, pa_account2),
      benchmarks = list(pa_benchmark1),
      dates = pa_dates
    )
  )

  # Create Calculation ----------------
  calculation <- Calculation$new(pa = paCalculations)

  calculationsApi <- CalculationsApi$new(apiClient = apiClient)

  runCalculationResponse <- tryCatch(
   calculationsApi$RunCalculationWithHttpInfo(calculation = calculation),
   ApiException = function(ex) ex
  )
  if(!is.null(runCalculationResponse$ApiException)){
    cat(runCalculationResponse$ApiException$toString())
    stop("Api exception encountered")
  }

  locationList <- strsplit(runCalculationResponse$response$headers$location, split = "/")
  calculationId <- tail(unlist(locationList), n = 1)
  print(paste("Calculation Id:", calculationId))

  # Get Calculation Status ----------------
  getCalculationStatusResponse <- tryCatch(
    calculationsApi$GetCalculationStatusByIdWithHttpInfo(id = calculationId),
    ApiException = function(ex) ex
  )
  if(!is.null(getCalculationStatusResponse$ApiException)){
    cat(getCalculationStatusResponse$ApiException$toString())
    stop("Api exception encountered")
  }

  while (getCalculationStatusResponse$response$status_code == 200
         && (getCalculationStatusResponse$content$status == "Queued" || getCalculationStatusResponse$content$status == "Executing")) {
    maxAge <- 5
    if ("cache-control" %in% names(getCalculationStatusResponse$response$headers)) {
      maxAge <- as.numeric(unlist(strsplit(getCalculationStatusResponse$response$headers$`cache-control`, "="))[2])
    }
    print(paste("Sleeping:", maxAge, "secs"))
    Sys.sleep(maxAge)

    getCalculationStatusResponse <- tryCatch(
      calculationsApi$GetCalculationStatusByIdWithHttpInfo(id = calculationId),
      ApiException = function(ex) ex
    )
    if(!is.null(getCalculationStatusResponse$ApiException)){
     cat(getCalculationStatusResponse$ApiException$toString())
     stop("Api exception encountered")
    }
  }

  print("Calculation Completed!!!");

  # Get Result of Calculation Units ----------------
  utilityApi <- UtilityApi$new(apiClient = apiClient)
  tables <- list()

  for (calculationUnitId in names(getCalculationStatusResponse$content$pa)) {
    if(getCalculationStatusResponse$content$pa[[calculationUnitId]]$status == "Success") {
      getCalculationUnitResultResponse <- tryCatch(
        utilityApi$GetByUrlWithHttpInfo(url = getCalculationStatusResponse$content$pa[[calculationUnitId]]$result),
        ApiException = function(ex) ex
      )
      if(!is.null(getCalculationUnitResultResponse$ApiException)){
        cat(getCalculationUnitResultResponse$ApiException$toString())
        stop("Api exception encountered")
      }

      print(paste("Calculation Unit Id :", calculationUnitId, "Succeeded!!!"));

      package <- read(factset.protobuf.stach.Package, getCalculationUnitResultResponse$content)

      stachExtension <- StachExtensions$new()

      # Converting result to data frame
      tables[[calculationUnitId]] <- stachExtension$ConvertToDataFrame(package)

      # Uncomment below line to dump data frame to .csv files
      # dataFramesList <- tables[[calculationUnitId]]
      # for (dataFrameId in names(dataFramesList)) {
      #   write.table(dataFramesList[[dataFrameId]], file = paste(dataFrameId, ".csv", sep = ""), sep = ",", row.names = FALSE)
      # }

      # Printing first 6 records in the first data frame to console
      print(paste("Printing first 6 records in the first data frame"));
      print(head(tables[[1]][[1]]))
    }
    else{
      print(paste("Calculation Unit Id:", calculationUnitId, " Failed!!!"))
      print(paste("Error message:", getCalculationStatusResponse$content$pa[[calculationUnitId]]$error))
    }
  }
}

main()