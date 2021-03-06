library(factset.analyticsapi.engines)
library(factset.protobuf.stach)
library(httr)

username <- "<username-serial>"
password <- "<apikey>"
url <- "https://api.factset.com"

spar_document <- "SPAR_DOCUMENTS:Factset Default Document"
spar_account1 <- SPARIdentifier$new(id = "R.1000", returntype = "GTR", prefix = "RUSSELL")
spar_account2 <- SPARIdentifier$new(id = "R.2000", returntype = "GTR", prefix = "RUSSELL")
spar_benchmark <- SPARIdentifier$new(id = "R.2000", returntype = "GTR", prefix = "RUSSELL")
spar_dates <- SPARDateParameters$new(startdate = "20180101", enddate = "20181231", frequency = "Monthly")
spar_component_name = "Returns Table"
spar_component_category = "Raw Data / Returns"

apiClient <- ApiClient$new(basePath = url, username = username, password = password)

componentsApi <- ComponentsApi$new(apiClient = apiClient)

main <- function (){
  # Build SPAR Calculation Parameters List ----------------
  components <- tryCatch(
    componentsApi$GetSPARComponents(document = spar_document),
    ApiException = function(ex) ex
  )
  if(!is.null(components$ApiException)){
    cat(components$ApiException$toString())
    stop("Api exception encountered")
  }

  componentId <- ""

  for (id in names(components)) {
    if(components[[id]]$name == spar_component_name && components[[id]]$category == spar_component_category) {
      componentId <- id
      break
    }
  }

  if(componentId == "") {
    print(paste("Component Id not found for Component Name", spar_component_name, "and Component Category", spar_component_category))
    stop("Invalid Component Id Error")
  }

  print(paste("SPAR Component Id:", componentId))

  sparCalculations <- list(
    "1" = SPARCalculationParameters$new(
      componentid = componentId,
      accounts = list(spar_account1, spar_account2),
      benchmark = spar_benchmark,
      dates = spar_dates
    )
  )

  # Create Calculation ----------------
  calculation <- Calculation$new(spar = sparCalculations)

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

  for (calculationUnitId in names(getCalculationStatusResponse$content$spar)) {
    if(getCalculationStatusResponse$content$spar[[calculationUnitId]]$status == "Success") {
      getCalculationUnitResultResponse <- tryCatch(
        utilityApi$GetByUrlWithHttpInfo(url = getCalculationStatusResponse$content$spar[[calculationUnitId]]$result),
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
      print(paste("Calculation Unit Id:", calculationUnitId, "Failed!!!"))
      print(paste("Error message:", getCalculationStatusResponse$content$spar[[calculationUnitId]]$error))
    }
  }

}

main()