#' @title Obtain timeSeries from WTSS server, based on a CSV file.
#' @name sits_fromCSV
#'
#' @description reads descriptive information about a set of
#' spatio-temporal locations from a CSV file. Then, it uses the WTSS time series service
#' to retrieve the time series, and stores the time series on a SITS tibble for later use.
#' The CSV file should have the following column names:
#' "longitude", "latitude", "start_date", "end_date", "label"
#'
#' @param csv_file        string  - name of a CSV file with information <id, latitude, longitude, from, end, label>
#' @param service         string - name of the time series service (options are "WTSS" or "SATVEG")
#' @param coverage        string - the name of the coverage to be retrieved
#' @param bands           string vector - the names of the bands to be retrieved
#' @param satellite       (optional) - the same of the satellite (options - "terra", "aqua", "comb")
#' @param prefilter       string ("0" - none, "1" - no data correction, "2" - cloud correction, "3" - no data and cloud correction)
#' @param n_max           integer - the maximum number of samples to be read
#' @return data.tb        a SITS tibble
#'
#' @examples
#' \donttest{
#' #' # Read a set of points defined in a CSV file from a WTSS server
#' csv_file <- system.file ("extdata/samples/samples_import.csv", package = "sits")
#' points.tb <- sits_fromCSV (file = csv_file)
#' }
#' @export

sits_fromCSV <-  function(csv_file,
                          service = "WTSS",
                          coverage = "mod13q1_512",
                          bands = NULL,
                          satellite = "terra",
                          prefilter = "1",
                          n_max = Inf) {

    # load the configuration file
    if (!exists("config_sys"))
        config_sits <- sits_config()

    # check that the input is a CSV file
    ensurer::ensure_that(csv_file, !purrr::is_null(.) && tolower(tools::file_ext(.)) == "csv",
                         err_desc = "sits_fromCSV: please provide a valid CSV file")

    # Ensure that the service is available
    ensurer::ensure_that(service, (.) %in% config_sits$ts_services,
                         err_desc = "sits_getdata: Invalid time series service")

    # if the server is a WTSS service, check that the coverage name exists
    if (service == "WTSS") {
        # obtains information about the WTSS service
        URL              <- config_sits$WTSS_server
        wtss.obj         <- wtss::WTSS(URL)
        # obtains information about the coverages
        coverages.vec    <- wtss::listCoverages(wtss.obj)
        # is the coverage in the list of coverages?
        ensurer::ensure_that(coverage, (.) %in% coverages.vec,
                             err_desc = "sits_fromCSV: coverage is not available in the WTSS server")
    }

    # configure the format of the CSV file to be read
    cols_csv <- readr::cols(id          = readr::col_integer(),
                            longitude   = readr::col_double(),
                            latitude    = readr::col_double(),
                            start_date  = readr::col_date(),
                            end_date    = readr::col_date(),
                            label       = readr::col_character())
    # read sample information from CSV file and put it in a tibble
    csv.tb <- readr::read_csv(csv_file, n_max = n_max, col_types = cols_csv)

    # create a variable to test the number of samples
    n_samples_ref <-  -1
    # create a variable to store the number of rows
    nrow <- 0
    # create a vector to store the lines with different number of samples
    diff_lines <- vector()
    # create the tibble
    data.tb <- sits_tibble()
    # for each row of the input, retrieve the time series
    csv.tb %>%
        purrrlyr::by_row(function(r){
            row <- sits_from_service(service, r$longitude, r$latitude, r$start_date, r$end_date,
                                     coverage, bands, satellite, prefilter, r$label)
            nrow <-  nrow + 1
            # ajust the start and end dates
            row$start_date <- lubridate::as_date(utils::head(row$time_series[[1]]$Index, 1))
            row$end_date   <- lubridate::as_date(utils::tail(row$time_series[[1]]$Index, 1))

            n_samples <- nrow(row$time_series[[1]])
            if (n_samples_ref == -1 )
                n_samples_ref <<- n_samples
            else
                if (n_samples_ref != n_samples) {
                    diff_lines[length(diff_lines) + 1 ] <<- nrow
                }

            data.tb <<- dplyr::bind_rows(data.tb, row)
        })
    if (length(diff_lines) > 0) {
        if (length(diff_lines) == (nrow(csv.tb) - 1))
            message("First line has different number of samples than others")
        else
            message("Some lines have different number of samples than the first line")
    }

    return(data.tb)
}
#' @title Export a tibble data to the CSV format
#' @name sits_toCSV
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description Converts data from a SITS tibble to a CSV file
#'
#' @param  data.tb    a SITS time series
#' @param  file       the name of the CSV file to be exported
#' @return status     the status of the operation
#' @examples
#' \donttest{
#' # read a tibble with 400 samples of Cerrado and 346 samples of Pasture
#' data(cerrado_2classes)
#' # export a time series to zoo
#' sits_toCSV (cerrado_2classes, file = "./cerrado_2classes.csv")
#' }
#' @export
sits_toCSV <- function(data.tb, file){

    # load the configuration file
    if (!exists("config_sys"))
        config_sits <- sits_config()

    #select the parts of the tibble to be saved
    csv.tb <- dplyr::select(data.tb, config_sits$csv_columns)

    # create a column with the id
    id.tb <- tibble::tibble(id = 1:NROW(csv.tb))

    # join the two tibbles
    csv.tb <- dplyr::bind_cols(id.tb, csv.tb)

    # write the CSV file
    utils::write.csv(csv.tb, file, row.names = FALSE, quote = FALSE)

    return(invisible(TRUE))
}

