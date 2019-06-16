disable("mappdf")
FS<-'SHIP'
values <- reactiveValues()
df <- reactive({
  # input$file will be NULL initially. After the user selects
  # and uploads a file, it will be a data frame with 'name',
  # 'size', 'type', and 'datapath' columns. The 'datapath'
  # column will contain the local filenames where the data can
  # be found.
  
  inFile <- input$egcanada

  if (is.null(inFile)){
    return("")
  }else{
    x<-read.csv(inFile$datapath, header = TRUE, stringsAsFactors = FALSE)
    x$time<-mdy_hm(x$time)
    values$sigdate<-unique(date(x$time))
    values$webshotpath<-paste0(getwd(),"/",values$sigdate,"_map")
    
    read.csv(inFile$datapath, header = TRUE, stringsAsFactors = FALSE)
    }
  })
##observe looks at reactive but does not produce anything
observe({
  egdaily<-df()
  if(egdaily != ""){
    withProgress(message = 'Analyzing sightings for new protection zones...', value = 0, {
    shapepath<-"./shapefiles"
    
    source('./scripts/shapefiles.R', local = TRUE)$value
    incProgress(1/5)
    source('./scripts/trigger analysis.R', local = TRUE)$value
    enable("mappdf")
    
    ##table for core area boundaries
    values$bounds<-bounds%>%
      filter(VERTEX != 5)
    output$corebounds<-renderTable({values$bounds},  striped = TRUE)
    })
  }

})
    output$mappdf<-downloadHandler(
      
      filename = function() {
        paste0(values$sigdate,"_Shipping_Trigger_Analysis.pdf")},
      content = function(file) {
        tempReport<-file.path("./scripts/SHIP_TrigAnalysisPDF.Rmd")
        
        file.copy("SHIP_TrigAnalysisPDF.Rmd", tempReport, overwrite = FALSE)
        print("button pressed")
        
        params<-list(sigdate = values$sigdate, webshotpath = values$webshotpath, bounds = values$bounds)
        
        rmarkdown::render(tempReport, output_file = file,
                          params = params,
                          envir = new.env(parent = globalenv())
        )
        })
    


