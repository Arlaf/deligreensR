library(shiny)
library(shinydashboard)
library(shinyjs)
library(dplyr)
library(plotly)
library(lubridate)
library(RPostgreSQL)
library(sqldf)
library(leaflet)
library(sp)
library(maptools)
library(geojsonio)
library(htmltools)

###### FONCTIONS #########
verif_tz <- function(df){
  # Si le dataframe passé en paramètre contient des colonnes de POSIXct, la fonction lance la fonction correction_tz sur chacune d'entre elles
  n <- ncol(df)
  posix_found <- F
  i <- 1
  # Recherche de posix
  while(!posix_found & i <= n){
    if(is.POSIXct(df[,i])){
      posix_found <- T
    }
    i <- i + 1
  }
  # Correction si il y a des posix
  if(posix_found){
    # identification des colonnes de POSIXct
    cols <- sapply(df, is.POSIXct)
    # Si il y a plusieurs colonnes de POSIXct
    if(sum(cols) > 1){
      # Création d'un dataframe contenant les bonnes dates
      a <- df[,cols] %>%
        lapply(correction_tz) %>%
        as.data.frame()
      # Collage des dataframe
      df <- cbind(df[,!cols],a)
      # Si il n'y a qu'une seule colonne de POSIXct
    }else{
      df[,which(cols)] <- correction_tz(df[,which(cols)])
    }
    
  }
  df
}

correction_tz <- function(x){
  # Lit un vecteur de date en UTC pour les convertir en CET / CEST
  x <- as.POSIXct(as.character(x),tz = "UTC")
  attr(x, "tzone") <- "Europe/Paris"
  x
}

extract_core <- function(req){
  
  dbname <- Sys.getenv("dbname")
  dbhost <- Sys.getenv("dbhost")
  dbuser <- Sys.getenv("dbuser")
  dbpass <- Sys.getenv("dbpass")
  
  # loads the PostgreSQL driver
  drv <- dbDriver("PostgreSQL")
  # creates a connection to the postgres database
  # note that "con" will be used later in each connection to the database
  con <- dbConnect(drv, 
                   dbname = dbname,
                   host = dbhost, 
                   port = 5432,
                   user = dbuser, 
                   password = dbpass)
  options(sqldf.RPostgreSQL.user = dbuser, 
          sqldf.RPostgreSQL.password = dbpass,
          sqldf.RPostgreSQL.dbname = dbname,
          sqldf.RPostgreSQL.host = dbhost, 
          sqldf.RPostgreSQL.port = 5432)
  
  df <- sqldf(req)
  
  # close the connection
  dbDisconnect(con)
  dbUnloadDriver(drv)
  
  # Correction des Time Zones :
  # Les données sont stockées en UTC mais lues en CET/CEST par R
  df <- verif_tz(df)
  
  df
}

email_equipier <- c('dumontet.thibaut@gmail.com', 'dumontet.julie@gmail.com', 'laura.h.jalbert@gmail.com', 'rehmvincent@gmail.com', 'a.mechkar@gmail.com', 'helena.luber@gmail.com', 'martin.plancquaert@gmail.com', 'badieresoscar@gmail.com', 'steffina.tagoreraj@gmail.com', 'perono.jeremy@gmail.com', 'roger.virgil@gmail.com', 'boutiermorgane@gmail.com', 'idabmat@gmail.com', 'nadinelhubert@gmail.com', 'faure.remi@yahoo.fr', 'maxime.cisilin@gmail.com', 'voto.arthur@gmail.com')
zone1 <- c("69001",
           "69002",
           "69003",
           "69004",
           "69005",
           "69006",
           "69007",
           "69008",
           "69009",
           "69100",
           "69110",
           "69350",
           "69600")
zone2 <- c("69120",
           "69130",
           "69160",
           "69190",
           "69200",
           "69230",
           "69300",
           "69310",
           "69340",
           "69370",
           "69410",
           "69450",
           "69500",
           "69660")
zone3 <- c("69126",
           "69140",
           "69150",
           "69250",
           "69260",
           "69270",
           "69280",
           "69290",
           "69320",
           "69330",
           "69360",
           "69390",
           "69530",
           "69540",
           "69570",
           "69580",
           "69630",
           "69650",
           "69680",
           "69730",
           "69740",
           "69760",
           "69780",
           "69800",
           "69890",
           "69960")

###### INITIALISATION ######
format_date <- "%d %b %y"

# Chartre graphique
rouge <-"#EC7963"
bleu <- "#584E7C"
vert <- "#77D7D2"

rv <- reactiveValues()

rv$verified <- F

##### SERVEUR #######
shinyServer(function(input, output, session) {
  
  ################# FONCTIONS ############ 
  session$onSessionEnded(stopApp)
  
  # Importation des données et premiers calculs
  import_data <- reactive({
    print("import_data")
    req <- "SELECT 	o.id AS order_id,
                  	o.order_number,
                    o.client_id,
                  	o.created_at,
                  	o.financial_status,
                  	o.total_price_cents,
                  	o.pickup,
                  	o.total_tax_cents,
                  	o.total_shipping_cents,
                  	o.total_discounts_cents,
                  	c.created_at AS client_created_at,
                  	c.email,
                    ci.zip_code,
                  	c.first_order_date,
                  	sum(l.buying_price_cents * l.quantity) AS cogs
          FROM clients c, orders o, line_items l, contact_informations ci
          WHERE o.id = l.order_id AND o.client_id = c.id AND ci.id = o.contact_information_id
          GROUP BY  o.id,
                    o.order_number,
                    o.client_id,
                  	o.created_at,
                  	o.financial_status,
                  	o.total_price_cents,
                  	o.pickup,
                  	o.total_tax_cents,
                  	o.total_shipping_cents,
                  	o.total_discounts_cents,
                  	c.created_at,
                  	c.email,
                    ci.zip_code,
                  	c.first_order_date"
    df <- extract_core(req)
    
    df <- df %>%
      filter(order_id != 666) %>%
      mutate(date = as.Date(created_at),
             semaine = floor_date(date, unit = "week", week_start = getOption("lubridate.week.start", 1)),
             mois = floor_date(date, unit = "month"),
             age = as.numeric(difftime(created_at, first_order_date, units = "min")),
             premiere = age < 60,
             equipier = grepl("@deligreens.com$",email) | email %in% email_equipier,
             marge = total_price_cents - cogs,
             zone = NA)
    
    df$zone[df$zip_code %in% zone1] <- 1
    df$zone[df$zip_code %in% zone2] <- 2
    df$zone[df$zip_code %in% zone3] <- 3
    
    # Résultats par semaine par défaut
    df$group <- df$semaine
    df$lib <- paste("Semaine du", format(df$group, format_date))
    
    df
  })
  
  # Filtrage des commandes
  reac_filtres <- reactive({
    print("reac_filtre")
    df <- import_data()
    
    # Filtre sur les équipiers
    if(input$equipier){
      df <- df %>%
        filter(!equipier)
    }
      
    # Filtre sur la plage de date
    df <- df %>%
      filter(date >= input$dates[1] & date <= input$dates[2])
    
    # Filtre sur le type de commande
    if(input$type_commande == "livr"){
      df <- df %>%
        filter(!pickup)
    }else if(input$type_commande == "pick"){
      df <- df %>%
        filter(pickup)
    }
    
    if(input$periode == "Jour"){
      df$group <- df$date
      df$lib <- paste("Le", format(df$group, "%A"), format(df$group, format_date))
      # periode_en_cours <- Sys.Date()
    }else if(input$periode == "Semaine"){
      df$group <- df$semaine
      df$lib <- paste("Semaine du", format(df$group, format_date))
      # periode_en_cours <- floor_date(Sys.Date(), unit = "week", week_start = getOption("lubridate.week.start", 1))
    }else {
      df$group <- df$mois
      df$lib <- format(df$group, "%B")
      # periode_en_cours <- floor_date(Sys.Date(), unit = "month")
    }
    
    # Identification des nouveaux clients de la période (group)
    cli <- df %>%
      group_by(group, lib, client_id) %>%
      # Si le client a effectué sa première commande dans cette periode alors il est considéré comme nouveau client
      summarise(nouveau = as.logical(max(premiere)))
    
    df <- left_join(df, cli, by = c("group" = "group", "lib" = "lib", "client_id" = "client_id"))
    
    # Filtre sur le type de client
    if(input$type_client == "rep"){
      df <- df %>%
        filter(!nouveau)
      cli <- cli %>%
        filter(!nouveau)
    }else if(input$type_client == "new"){
      df <- df %>%
        filter(nouveau)
      cli <- cli %>%
        filter(nouveau)
    }
    
    # sortie <- list(df, cli, periode_en_cours)
    sortie <- list(df, cli)
    sortie
  })
  
  # Clic sur le bouton valider à la demande de password
  observeEvent(input$go,{
    if(input$pwd == Sys.getenv("login_password")){
      rv$verified <- T
    }
  })
  
  # A l'identification : activation du dashboard général
  observeEvent(rv$verified,{
    isolate({updateTabItems(session, "tabs", "tab_general")})
  })
  
  ################## GRAPHIQUES ##################
  
  # Clients
  output$clients <- renderPlotly({
    cli <- reac_filtres()[[2]]
    
    # Nombre de nouveaux clients par période
    cli <- cli %>%
      group_by(group, lib) %>%
      summarise(nb_cli = n(),
                nb_nouv = sum(nouveau, na.rm = T)) %>%
      mutate(nb_anc = nb_cli - nb_nouv)

    g1 <- plot_ly(cli, x = ~group, y = ~nb_anc, type = 'bar', name = "Repeat",
                  marker = list(color = vert),
                  text = ~nb_anc,
                  textposition = "auto",
                  hoverinfo = "text",
                  hovertext = ~paste(lib,
                                    '<br>Nb =', nb_anc,
                                    '<br>Pct =', round(nb_anc*100/nb_cli,1),"%")) %>%
      add_trace(y = ~nb_nouv, name = 'New',
                marker = list(color = rouge),
                text = ~nb_nouv,
                textposition = "auto",
                hoverinfo = "text",
                hovertext = ~paste(lib,
                                  '<br>Nb =', nb_nouv,
                                  '<br>Pct =', round(nb_nouv*100/nb_cli,1),"%")) %>%
      layout(yaxis = list(title = 'Nombre de clients'),
             xaxis = list(title = input$periode,
                          tickvals = ~group,
                          ticktext = ~if(input$periode == "Mois"){lib}else{format(group,"%d/%m")}),
             barmode = 'stack')
    g1
  })
  
  # Marge et panier moyen
  output$panier <- renderPlotly({
    df <- reac_filtres()[[1]]
    
    # Calcul du panier moyen par période
    moy <- df %>%
      group_by(group, lib) %>%
      summarise(mean = mean(total_price_cents/100),
                marge = mean(marge/100),
                discount = mean(total_discounts_cents/100)) %>%
      ungroup()
    # La borne supérieure de la graduation
    max <- ceiling(max(moy$mean) * 1.1)

    g1 <- plot_ly(data = moy,
                  x = ~group,
                  y = ~mean,
                  marker = list(color = bleu),
                  line = list(color = bleu),
                  name = "Panier moyen",
                  type ="scatter",
                  mode = "lines+markers",
                  hoverinfo = "text",
                  hovertext = ~paste(lib,
                                     '<br>Panier moyen =', paste(format(round(mean,2), big.mark=" ", decimal.mark=","),"€"))) %>%
      add_trace(y = ~marge,
                marker = list(color = rouge),
                line = list(color = rouge),
                name = "Marge moyenne",
                mode = "lines+markers",
                hoverinfo = "text",
                hovertext = ~paste(lib,
                                   '<br>Marge moyenne =', paste(format(round(marge,2), big.mark=" ", decimal.mark=","),"€"),
                                   '<br>Pct =', paste(round(100*marge/mean,1),"%"))) %>%
      add_trace(y = ~discount,
                marker = list(color = vert),
                line = list(color = vert),
                name = "Discounts",
                mode = "lines+markers",
                visible = "legendonly",
                hoverinfo = "text",
                hovertext = ~paste(lib,
                                   '<br>Discount moyenne =', paste(format(round(discount,2), big.mark=" ", decimal.mark=","),"€"))) %>%
      layout(xaxis = list(title = input$periode,
                          tickvals = ~group,
                          ticktext = ~if(input$periode == "Mois"){lib}else{format(group,"%d/%m")}),
             yaxis = list (title = "Panier moyen",
                           range = c(0, max)))
    g1
  })
  
  #Ventes brutes et nettes
  output$ventes <- renderPlotly({
    df <- reac_filtres()[[1]]
    
    ca <- df %>%
      group_by(group, lib) %>%
      summarise(brute = sum(total_price_cents/100),
                nette = sum(marge/100),
                discounts = sum(total_discounts_cents/100)) %>%
      ungroup()
    max <- ceiling(max(ca$brute) * 1.1)
    
    g1 <- plot_ly(data = ca,
                  x = ~group,
                  y = ~brute,
                  marker = list(color = bleu),
                  line = list(color = bleu),
                  name = "Ventes brutes",
                  type = "scatter",
                  mode = "lines+markers",
                  hoverinfo = "text",
                  hovertext = ~paste(lib,
                                     '<br>Ventes brutes =', paste(format(round(brute,2), big.mark=" ", decimal.mark=","),"€"))) %>%
      add_trace(y = ~nette,
                marker = list(color = rouge),
                line = list(color = rouge),
                name = "Ventes nettes",
                mode = "lines+markers",
                hoverinfo = "text",
                hovertext = ~paste(lib,
                                   '<br>Ventes nettes =', paste(format(round(nette,2), big.mark=" ", decimal.mark=","),"€"),
                                   '<br>Pct =', paste(round(100*nette/brute,1),"%"))) %>%
      add_trace(y = ~discounts,
                marker = list(color = vert),
                line = list(color = vert),
                name = "Discounts",
                mode = "lines+markers",
                visible = "legendonly",
                hoverinfo = "text",
                hovertext = ~paste(lib,
                                   '<br>Discounts =', paste(format(round(discounts,2), big.mark=" ", decimal.mark=","),"€"))) %>%
      layout(xaxis = list(title = input$periode,
                          tickvals = ~group,
                          ticktext = ~if(input$periode == "Mois"){lib}else{format(group,"%d/%m")}),
             yaxis = list (title = "Ventes",
                           range = c(0, max)))
    g1
  })
  
  # Nombre de commandes
  output$commandes <- renderPlotly({
    df <- reac_filtres()[[1]]
    
    com <- df %>%
      group_by(group, lib) %>%
      summarise(nb_tot = n(),
                nb_liv = sum(!pickup)) %>%
      mutate(nb_pick = nb_tot - nb_liv)
    
    # Borne supérieure du graphique : si on la laisse par défaut, certains labels du graphique dépassent du graphique (en hauteur)
    max <- max(com$nb_tot) * 1.1
    
    g1 <- plot_ly(com, x = ~group, y = ~nb_liv, type = 'bar', name = "Livraisons",
                  marker = list(color = vert),
                  text = ~nb_liv,
                  textposition = "auto",
                  hoverinfo = "text",
                  hovertext = ~paste(lib,
                                     '<br>Nb =', nb_liv,
                                     '<br>Pct =', round(nb_liv*100/nb_tot,1),"%")) %>%
      add_trace(y = ~nb_pick, name = 'Pickup',
                marker = list(color = rouge),
                text = ~nb_pick,
                textposition = "auto",
                hoverinfo = "text",
                hovertext = ~paste(lib,
                                   '<br>Nb =', nb_pick,
                                   '<br>Pct =', round(nb_pick*100/nb_tot,1),"%")) %>%
      layout(yaxis = list(title = 'Nombre de commandes',
                          range = c(0,max)),
             xaxis = list(title = input$periode,
                          tickvals = ~group,
                          ticktext = ~if(input$periode == "Mois"){lib}else{format(group,"%d/%m")}),
             barmode = 'stack')
    
    g1
  })
  
  # Codes postaux
  output$code_postaux <- renderPlotly({
    df <- reac_filtres()[[1]]
    
    geo <- df %>%
      filter(!pickup) %>%
      group_by(group, zip_code) %>%
      summarize(nb_com = n(),
                nb_cli = n_distinct(client_id),
                nb_new = n_distinct(client_id[nouveau]),
                nb_old = nb_cli - nb_new,
                ca = sum(total_price_cents)/100) %>%
      ungroup()
    
    g1 <- plot_ly()
    
    for (cp in sort(unique(df$zip_code))){
      g1 <- add_trace(g1,
                      data = geo[geo$zip_code == cp,],
                      x = ~group,
                      y = ~nb_com,
                      type = "scatter",
                      mode = "lines+markers",
                      name = paste(cp," "))
    }
    g1
  })
  
  ################## INFOBOX ##################
  output$box_panier <- renderValueBox({
    df <- reac_filtres()[[1]]
    val <- mean(df$total_price_cents/100) %>%
      round(2)
    valueBox(value = paste(format(val, big.mark = " ", scientific = F, decimal.mark = ","), "€"),
             subtitle = tags$p(style = "font-size: 16px;", "Panier moyen"),
             icon = icon("shopping-basket"),
             color = "light-blue")
  })
  
  output$box_clients <- renderValueBox({
    df <- reac_filtres()[[1]]
    val <- length(unique(df$client_id))
    valueBox(value = format(val, scientific = F, big.mark = " "),
             subtitle = tags$p(style = "font-size: 16px;", "Nombre de clients"),
             icon = icon("group"),
             color = "blue")
  })
  
  output$box_ventes <- renderValueBox({
    df <- reac_filtres()[[1]]
    val <- round(sum(df$total_price_cents/100),0)
    valueBox(value = paste(format(val, big.mark = " ", scientific = F), "€"),
             subtitle = tags$p(style = "font-size: 16px;", "Ventes brutes"),
             icon = icon("eur"),
             color = "aqua")
  })
  
  output$box_com <- renderValueBox({
    df <- reac_filtres()[[1]]
    val <- nrow(df)
    valueBox(value = format(val, scientific = F, big.mark = " "),
             subtitle = tags$p(style = "font-size: 16px;", "Nombre de commandes"),
             icon = icon("external-link-square"),
             color = "purple")
  })
  
  ################## UI ##################
  # Sidebar
  output$sidebar <- renderUI({
    if(rv$verified){
      tagList(
        sidebarMenu(id = "tabs",
                    menuItem("Dashboard général", tabName = "tab_general", icon = icon("dashboard")),
                    menuItem("Codes postaux", icon = icon("globe"), tabName = "tab_geo")
        ),
        h1(""),
        dateRangeInput("dates", 
                       label = "Dates",
                       format = "dd/mm/yyyy",
                       start = floor_date(Sys.Date(), unit = "weeks", week_start = getOption("lubridate.week.start", 1))-70,
                       end = floor_date(Sys.Date(), unit = "weeks", week_start = getOption("lubridate.week.start", 1))-1),
        radioButtons("type_commande", label = "Types de commandes", 
                     choices = list("Tous" = "tous", "Livraisons" = "livr", "Pickups" = "pick"),
                     selected = "tous"),
        radioButtons("type_client", label = "Types de clients", 
                     choices = list("Tous" = "tous", "Nouveaux clients" = "new", "Repeat customers" = "repeat"),
                     selected = "tous"),
        radioButtons("periode", label = "Regrouper",
                     choices = list("par mois" = "Mois", "par semaine" = "Semaine", "par jour" = "Jour"),
                     selected = "Semaine"),
        checkboxInput("equipier", label = "Enlever les équipiers", value = TRUE)
      )
    }
  })
  
  # Body
  output$body <- renderUI({
    if(rv$verified){
      
      tagList(
        ###### COULEURS STATUTS ######
        
        # PRIMARY
        tags$style(HTML("
                        .box.box-solid.box-primary>.box-header {
                        color:#fff;
                        background:#00C0EF}
                        .box.box-solid.box-primary{
                        border-bottom-color:#00C0EF;
                        border-left-color:#00C0EF;
                        border-right-color:#00C0EF;
                        border-top-color:#00C0EF;}
                        ")),
        
        # INFO
        tags$style(HTML("
                        .box.box-solid.box-info>.box-header {
                        color:#fff;
                        background:#3C8DBC}
                        .box.box-solid.box-info{
                        border-bottom-color:#3C8DBC;
                        border-left-color:#3C8DBC;
                        border-right-color:#3C8DBC;
                        border-top-color:#3C8DBC;}
                        ")),
        
        # WARNING
        tags$style(HTML("
                        .box.box-solid.box-warning>.box-header {
                        color:#fff;
                        background:#0073B7}
                        .box.box-solid.box-warning{
                        border-bottom-color:#0073B7;
                        border-left-color:#0073B7;
                        border-right-color:#0073B7;
                        border-top-color:#0073B7;}
                        ")),
        
        # SUCCESS
        tags$style(HTML("
                        .box.box-solid.box-success>.box-header {
                        color:#fff;
                        background:#605CA8}
                        .box.box-solid.box-success{
                        border-bottom-color:#605CA8;
                        border-left-color:#605CA8;
                        border-right-color:#605CA8;
                        border-top-color:#605CA8;}
                        ")),
        
        ###### CONTENU ######
        tabItems(
          tabItem(
            tabName = "tab_general",
            uiOutput("general")
          ),
          tabItem(
            tabName = "tab_geo",
            uiOutput("geo")
          )
        )
      )
    }else{
      tagList(
        box(width = 3,
            passwordInput("pwd", label = "Password", value =""),
            actionButton("go", label = "Valider")
        )
      )
    }
  })
  
  # Panels
  output$general <- renderUI({
    tagList(
      fluidRow(
        valueBoxOutput("box_ventes", width = 3),
        valueBoxOutput("box_panier", width = 3),
        valueBoxOutput("box_clients", width = 3),
        valueBoxOutput("box_com", width = 3)
      ),
      
      fluidRow(
        column(width = 6,
               box(title = "Ventes",
                   solidHeader = T,
                   status = "primary",
                   width = 12,
                   plotlyOutput("ventes", height = "250px")),
               box(title = "Marge et panier moyen",
                   solidHeader = T,
                   status = "info",
                   width = 12,
                   plotlyOutput("panier", height = "250px"))),
        column(width = 6,
               box(title = "Nombre de clients",
                   solidHeader = T,
                   status = "warning",
                   width = 12,
                   plotlyOutput("clients", height = "250px")),
               box(title = "Nombre de commandes",
                   solidHeader = T,
                   status = "success",
                   width = 12,
                   plotlyOutput("commandes", height = "250px")))
      )
    )
    
  })
  
  output$geo <- renderUI({
    tagList(
      fluidRow(
        column(width = 2, h1("")),
        column(width = 3,
               # align = "right",
               sliderInput("opac",
                           label = "Opacité",
                           min = 0,
                           max = 1,
                           step = 0.1,
                           value = 1)),
        column(width = 3,
               # align = "left",
               selectInput("choix_var", label = "Mesure à afficher", 
                           choices = list("Nombre de commandes" = "nb_com",
                                          "Nombre de clients" = "nb_cli",
                                          "Chiffre d'affaire TTC" = "ca"), 
                           selected = "nb_com")),
        column(width = 3,
               radioButtons("echelle", label = "Echelle", 
                            choices = list("Linéaire" = "lin", "Quadratique" = "quad", "Logarithmique" = "log"),
                            selected = "lin"))
        ),
      tags$style(type = "text/css", "#map {height: calc(100vh - 200px) !important;}"),
      leafletOutput("map"),
      plotlyOutput("code_postaux")
    )
  })
  
  ################## CARTE ##################
  prep_geo <- reactive({
    print("prep_geo")
    df <- reac_filtres()[[1]] 
    
    # Comptage du nombre de commandes par codes postaux
    df_cp <- df %>%
      filter(!pickup & !is.na(zip_code)) %>%
      group_by(zip_code) %>%
      summarise(nb_com = n(),
                nb_cli = n_distinct(client_id),
                ca = sum(total_price_cents/100)) %>%
      ungroup() %>% as.data.frame()
    
    # Importation des polygones des communes
    com <- geojsonio::geojson_read("./data_geo.geojson",
                                   what = "sp")
    # On ne garde que les zones qu'on livre
    com <- com[com$code_postal %in% c(zone1,zone2,zone3),]
    
    com$zone <- NA
    com$zone[com$code_postal %in% zone1] <- 1
    com$zone[com$code_postal %in% zone2] <- 2
    com$zone[com$code_postal %in% zone3] <- 3
    com$zone <- as.factor(com$zone)
    
    # Regroupement des polygones des communes par codes postaux
    cp <- unionSpatialPolygons(com, com$code_postal)
    
    # Regroupement des polygones des communes par zones
    zones <- unionSpatialPolygons(com, com$zone)
    
    # Liste complète des CP
    liste_cp <- names(cp)
    
    # Création d'un df qui contient tous les CP sans commandes
    df_cp2 <- data.frame(zip_code = liste_cp[!(liste_cp %in% df_cp$zip_code)],
                         nb_com = 0,
                         nb_cli = 0,
                         ca = 0)
    
    # Fusion des 2 df
    df_cp <- rbind(df_cp, df_cp2)
    rm(df_cp2)
    
    # Pour permettre la jointure avec le SP des codes postaux
    # Exactement les mêmes CP dans le df et le sp
    df_cp <- df_cp %>%
      filter(zip_code %in% liste_cp)
    # Noms des ligne = code postal
    rownames(df_cp) <- df_cp$zip_code
    
    # Jointure des polygones et des données
    cp <- addAttrToGeom(cp, df_cp, match.ID = T)
    
    # Ajout de la zone au sp
    # cp$zone <- NA
    # cp$zone[cp$zip %in% zone1] <- 1
    # cp$zone[cp$zip %in% zone2] <- 2
    # cp$zone[cp$zip %in% zone3] <- 3
    
    sortie <- list(com, cp, zones)
    sortie
  })
  
  output$map <- renderLeaflet({
    
    com <- prep_geo()[[1]]
    cp <- prep_geo()[[2]]
    zones <- prep_geo()[[3]]
    
    if(input$choix_var == "nb_com"){
      cp$val <- cp$nb_com
      titre <- "Nombre de commandes"
      # labels <- sprintf("<strong>%s</strong><br/>%g commandes",
      #                   cp$zip_code, cp$val) %>%
      #   lapply(htmltools::HTML)
      couleurs <- "Blues"
      # pal <- colorBin("Blues", domain = cp$val, bins = 9)
    }else if(input$choix_var == "nb_cli"){
      cp$val <- cp$nb_cli
      titre <- "Nombre de clients"
      # labels <- sprintf("<strong>%s</strong><br/>%g clients",
      #                   cp$zip_code, cp$val) %>%
      #   lapply(htmltools::HTML)
      couleurs <- "Reds"
    }else{
      cp$val <- cp$ca
      titre <- "Chiffre d'affaire TTC"
      # labels <- sprintf("<strong>%s</strong><br/>%s € de CA TTC",
      #                   cp$zip_code, format(round(cp$val), big.mark = " ", decimal.mark = ",", scientific = F)) %>%
      #   lapply(htmltools::HTML)
      couleurs <- "Greens"
    }
    
    # Labels
    labels <- sprintf("<strong>%s</strong><br/>%g commandes<br/>%g clients<br/>%s € de CA TTC",
                      cp$zip_code, cp$nb_com, cp$nb_cli, format(round(cp$ca), big.mark = " ", decimal.mark = ",", scientific = F)) %>%
      lapply(htmltools::HTML)
    
    # Palette de couleurs
    pal <- colorNumeric(couleurs, domain = if(input$echelle == "lin"){cp$val}else if(input$echelle == "quad"){sqrt(cp$val)}else{log(cp$val+1)})
    # bins <- seq(0,50,10)
    # pal <- colorBin("YlOrRd", domain = cp$nb_com, bins = bins)

    map <- leaflet() %>%
      # Fond de carte
      addProviderTiles("Esri.WorldStreetMap") %>%
      # Polygones des codes postaux
      addPolygons(data = cp,
                  fillColor = ~pal(if(input$echelle == "lin"){cp$val}else if(input$echelle == "quad"){sqrt(cp$val)}else{log(cp$val+1)}),
                  fillOpacity = input$opac,
                  weight = 1,
                  color = "white",
                  label = labels,
                  highlightOptions = highlightOptions(
                    color = "red",
                    opacity = 1,
                    weight = 2,
                    bringToFront = TRUE,
                    sendToBack = TRUE)) %>%
      # Lignes des communes
      addPolylines(data = com,
                   weight = 1,
                   color = "#EBEBEB") %>%
      # Lignes des codes postaux (pour les remettre devant les communes)
      addPolylines(data = cp,
                   weight = 2,
                   color = "#C2C2C2") %>%
      # Lignes des zones
      addPolylines(data = zones,
                   weight = 3,
                   color = "black") %>%
      # Marqueur de l'entrepot Deligreens
      addMarkers(lng = 4.813257264638196,
                 lat = 45.721664672462765,
                 label = "Deligreens") 
    
    # Légende seulement si échelle linéaire
    if(input$echelle == "lin"){
      map <- map %>%
        addLegend(position = "bottomright",
                  pal = pal,
                  values = cp$val,
                  title = titre,
                  labFormat = labelFormat(suffix = if(input$choix_var == "ca"){" €"}else{NULL}),
                  opacity = 1)
    }
    map
  })
  
})