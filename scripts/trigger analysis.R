######################
## Trigger Analysis ##
######################

egdaily$number<-as.numeric(egdaily$number)

egdaily$time<-mdy_hm(egdaily$time)
sigdate<-unique(date(egdaily$time))

sightID<-1:nrow(egdaily)
egdaily<-cbind(egdaily,sightID) #add SPM here if you decide to include

##copy for spatializing
eg<-egdaily
##declare which columns are coordinates
coordinates(eg)<-~lon+lat
##declare what kind of projection thy are in
proj4string(eg)<-CRS.latlon
##change projection
eg.tr<-spTransform(eg, CRS.new)

ymin = min(egdaily$lat) - 0.75
ymax = max(egdaily$lat) + 0.75
xmin = min(egdaily$lon) - 0.75
xmax = max(egdaily$lon) + 0.75

##trim the fishing grid to where the sightings are to speed it up bit
ATL_grid.crop<-st_crop(ATL_grid.sp, ymin = ymin, xmin = xmin, ymax = ymax, xmax = xmax)

#global options
###############################################
webshotpath<-paste0(getwd(),"/map")
print(webshotpath)
unlink("./*.png")

print("start html")
snap<-function(x,y){
  
  htmlwidgets::saveWidget(x, "temp.html", selfcontained = FALSE)
  webshot::webshot("temp.html", file = paste0("map",y,".png"), vwidth = 600, vheight = 450)
  
}
print("end html")

##evaluate sightings if in st. pierre et micquelon
#SPM<-!is.na(sp::over(eg.tr, as(spm, "SpatialPolygons")))
##consider adding something here that asks if sightings are in France (SPM)

######################
## trigger analysis ##
######################

egtrig<-egdaily

#spatial analysis
## 1 nautical mile is 1852 meters
m_nm<-1/1852
## eg density is 4 whales/100nm^2 (50 CFR Part 224)
egden<-0.0416

#######################################
## animals potential for aggregation ##
#######################################

  ##only taking ACTION_NEW = na
  actionna<-egtrig%>%
    ##calculates whale density radius
            mutate(corer = round(sqrt(number/(pi*egden)),2))%>%
            dplyr::select("time", "lat", "lon", "number","sightID","corer")
  ##distance between points matrix -- compares right whale sightings positions to each other
  combo<-reshape::expand.grid.df(actionna,actionna)
  names(combo)[7:12]<-c("time2","lat2","lon2","number2","sightID2","corer2")
  ##str(combo)
  
  ##calculates distance between points in nautical miles and the radii distance between points for trigger
  combo <- combo%>%
    mutate(dist_nm=geosphere::distVincentyEllipsoid(matrix(c(lon,lat), ncol = 2),
                                                    matrix(c(lon2, lat2), ncol =2), 
                                                    a=6378137, f=1/298.257222101)*m_nm,
           total_corer = corer + corer2)
  #print(combo)
  #filters out points compared where core radius is less than the distance between them and
  #keeps the single sightings where group size alone would be enough to trigger a DMA (0 nm dist means it is compared to itself)
  #I don't remember why I named this dmacand -- maybe dma combo and... then some?
  dmacand<-combo %>%
    dplyr::filter((dist_nm != 0 & dist_nm <= total_corer) | (number > 2 & dist_nm == 0))
  print("dmacand")
  print(dmacand)
  
  if (nrow(dmacand) == 0){
    output$trigmessage<-renderText({"Sightings do not trigger the aggregation criteria"})
  }
  ##filters for all distinct sightings that should be considered for DMA calculation
  dmasightID<-data.frame(sightID = c(dmacand$sightID,dmacand$sightID2)) %>%
    distinct()
  
  ##the below filters for sightings that are good for zone calc (are in the dmasightID list)

  zonesig<-egdaily%>%
    right_join(dmasightID, by = "sightID")
  
  #print(zonesig)
  ##############

################
##Create Zone ##
################
incProgress(1/5) #for progress bar

if (nrow(zonesig) > 0){
  ##############################
  ##CREATING a management zone##
  ##############################

  dmasights<-zonesig%>%
    dplyr::select(time,lat,lon,number,sightID)%>%
    distinct(time,lat,lon,number,sightID)%>%
    mutate(corer=round(sqrt(number/(pi*egden)),2))%>%
    as.data.frame()
  #print(dmasights)
  #str(dmasights)
  
  PolyID<-rownames(dmasights)
  #print(PolyID)
  #core radius in meters
  dmasights<-dmasights%>%
    mutate(corer_m = corer*1852,
           PolyID = 1:nrow(dmasights))
  
  #copy for spatializing
  dmadf<-dmasights
  
  ########################
  ## df to spatial object ##
  ########################
  ##declare which values are coordinates
  coordinates(dmadf)<-~lon+lat
  ##declare what projection they are in
  proj4string(dmadf)<-CRS.latlon
  ##transform projection
  dmadf.tr<-spTransform(dmadf, CRS.utm)
  ###########
  
  ##gbuffer needs utm to calculate radius in meters
  dmabuff<-gBuffer(dmadf.tr, byid=TRUE, width = dmadf$corer_m, capStyle = "ROUND")
  #print(dmabuff)
  ##data back to latlon dataframe
  ##this will be used later when sightings are clustered by overlapping core radiis
  clustdf<-spTransform(dmadf.tr, CRS.latlon)
  clustdf<-as.data.frame(clustdf)
  
  ##creates a dataframe from the density buffers put around sightings considered for DMA analysis
  polycoord<-dmabuff %>% fortify() %>% dplyr::select("long","lat","id")
  ##poly coordinates out of utm
  coordinates(polycoord)<-~long+lat
  proj4string(polycoord)<-CRS.utm
  polycoord.tr<-spTransform(polycoord, CRS.latlon)
  polycoorddf<-as.data.frame(polycoord.tr)
  
  #############           
  ## the circular core areas are the polygons in the below section
  idpoly<-split(polycoorddf, polycoorddf$id)
  
  idpoly<-lapply(idpoly, function(x) { x["id"] <- NULL; x })
  
  pcoord<-lapply(idpoly, Polygon)
  
  pcoord_<-lapply(seq_along(pcoord), function(i) Polygons(list(pcoord[[i]]), ID = names(idpoly)[i]))
  
  polycoorddf_sp<-SpatialPolygons(pcoord_, proj4string = CRS.latlon)
  #print(polycoorddf_sp)
  #print(str(polycoorddf_sp))
  ##############
  if (length(names(idpoly)) > 1){
    ##Overlap of whale density core area analysis
    polycomb<-data.frame(poly1=NA,poly2=NA,overlap=NA)
    ##creates a list of 2 combinations to compare
    #print(names(idpoly))
    combos<-combn(names(idpoly),2)
    ##compares the list
    for(i in seq_along(combos[1,])){
      poly1 <- combos[1,i]
      poly2 <- combos[2,i]
      #if they don't overlap, the result of the below "if statement" is NULL
      if(!is.null(gIntersection(polycoorddf_sp[poly1], polycoorddf_sp[poly2], byid = TRUE))){
        overlap = 'yes'
      } else {
        overlap = 'no'
      }
      df<-data.frame(poly1=poly1,poly2=poly2,overlap=overlap)
      polycomb<-rbind(polycomb,df)
    }
    
    polycomb$poly1<-as.numeric(polycomb$poly1)
    polycomb$poly2<-as.numeric(polycomb$poly2)
    polycluster<-polycomb%>%filter(!is.na(poly1))
  } else if (length(names(idpoly)) == 1) {
    polycluster<-data.frame(poly1 = 1, poly2 = 1, overlap = 'no')
  }
  
  ####clustering polygons that overlap
  polycluster_yes<-polycluster%>%
    filter(overlap=="yes")
  
  ###transitive property of oberlapping core areas
  polymat = graph_from_edgelist(as.matrix(polycluster_yes[,1:2]), directed=FALSE)
  #unique polygons
  upoly = sort(unique(c(polycluster_yes$poly1, polycluster_yes$poly2)))
  (cluster = components(polymat)$membership[upoly])
  #final cluster assignment df for overlap = yes
  (polyassign = data.frame(upoly, cluster, row.names=NULL))
  
  poly12<-rbind(unlist(polycluster$poly1),unlist(polycluster$poly2))
  poly12 <- data.frame(upoly = c(polycluster$poly1,polycluster$poly2))
  
  ##these sightings are NOT triggering on their own (or are trigger by one sighting of 3+ without overlapping sightings) are assigned a cluster of -1
  not<-poly12%>%
    filter((!poly12$upoly %in% polyassign$upoly) | (!poly12$upoly %in% polyassign$upoly))%>%
    distinct()%>%
    mutate(cluster = -1)
  
  ##put together the trigger sightings that don't overlap with any other sightings, with those that do with assigned clusters
  totpolyassign<-rbind(polyassign,not)
  totpolyassign$cluster<-as.numeric(totpolyassign$cluster)
  #print(totpolyassign)
  ##clustmin is for a totpolyassign df without any overlapping triggers
  clustmin = 0
  ##assigns consecutive cluster numbers to those sightings that don't overlap, but are triggering all on their own
  for (i in 1:nrow(totpolyassign))
    if (totpolyassign$cluster[i] == -1 & max(totpolyassign$cluster) > 0){
      totpolyassign$cluster[i]<-max(totpolyassign$cluster)+1
    } else if (totpolyassign$cluster[i] == -1 & max(totpolyassign$cluster) < 0 ){
      totpolyassign$cluster[i]<-clustmin+1
    } else { 
    }
  
  incProgress(1/5) #for progress bar
  
  #########
  clustdf$PolyID<-as.numeric(clustdf$PolyID)
  clustdf<-full_join(clustdf,totpolyassign,by=c("PolyID"="upoly"))
  #print(clustdf)
  
  clusty<-clustdf%>%
    group_by(cluster)%>%
    mutate(totes = sum(number))%>%
    filter(totes >= 3)
  clustn<-clustdf%>%
    group_by(cluster)%>%
    mutate(totes = sum(number))%>%
    filter(totes < 3)
  
  #print(clusty)
  #print(clustn)
  
  polycoorddf$id<-as.numeric(polycoorddf$id)
  corepoly<-right_join(polycoorddf, clusty, by=c('id'='PolyID'))%>%
    dplyr::select("long","lat.x","id","time","number","corer","corer_m", "lon","lat.y","cluster")
  #print(corepoly)
  
  #################
  ## for DMA insert
  
  clustersigs<-clusty%>%
    dplyr::select(PolyID,cluster,time,number,sightID)
  #print(clustersigs)
  trigsize<-clustersigs %>% 
    group_by(cluster)%>%
    summarise(TRIGGER_GROUPSIZE = sum(number), TRIGGERDATE = min(time))
  #print(trigsize)
  #################
  
  ##gets to the core for the cluster
  polymaxmin<-corepoly %>%
    group_by(cluster) %>%
    summarise(maxlat = max(lat.x), minlat = min(lat.x), maxlon = max(long), minlon = min(long))%>%
    as.data.frame()
  #print(polymaxmin)
  
  ##corners
  corebounds_nw<-polymaxmin%>%
    dplyr::select(cluster,minlon, maxlat)%>%
    dplyr::rename("long" = "minlon", "lat" = "maxlat")
  
  corebounds_sw<-polymaxmin%>%
    dplyr::select(cluster,minlon, minlat)%>%
    dplyr::rename("long" = "minlon", "lat" = "minlat")
  
  corebounds_ne<-polymaxmin%>%
    dplyr::select(cluster,maxlon, maxlat)%>%
    dplyr::rename("long" = "maxlon", "lat" = "maxlat")

  corebounds_se<-polymaxmin%>%
    dplyr::select(cluster,maxlon, minlat)%>%
    dplyr::rename("long" = "maxlon", "lat" = "minlat")
  
  corebounds<-rbind(corebounds_nw,corebounds_sw,corebounds_se,corebounds_ne,corebounds_nw)
  
  ###################
  
  incProgress(1/5) #for progress bar
  #make the bounds a polygon
  IDclust<-split(corebounds, corebounds$cluster)
  
  IDclust<-lapply(IDclust, function(x) { x["cluster"] <- NULL; x })
  
  polyclust<-lapply(IDclust, Polygon)
  
  polyclust_<-lapply(seq_along(polyclust), function(i) Polygons(list(polyclust[[i]]), ID = names(IDclust)[i]))
  
  polyclust_sp<-SpatialPolygons(polyclust_, proj4string = CRS.latlon)
  
  polyclust_sp_df<-SpatialPolygonsDataFrame(polyclust_sp, data.frame(id = unique(corebounds$cluster), row.names = unique(corebounds$cluster)))
  
  bounds<-polyclust_sp %>%
    fortify() %>%
    mutate(LAT = round(lat, 2), LON = round(long, 2))%>%
    dplyr::select(id,order,LAT,LON)%>%
    dplyr::rename("ID" = "id", "VERTEX" = "order")
  
  centroid<-gCentroid(polyclust_sp,byid=TRUE)
  cent_df<-as.data.frame(centroid)
  cent_df<-cent_df%>%
    dplyr::rename("Latitude" = "y", "Longitude" = "x")%>%
    mutate(ID = 1:n())%>%
    dplyr::select(ID,Latitude, Longitude)
  #print(cent_df)
  values$cent_df<-cent_df
  output$centroidtable<-renderTable({cent_df},  striped = TRUE)
  
  egtrig<-egtrig%>%
    mutate(corer=round(sqrt(number/(pi*egden)),2))
  
  #############
  ## mapping ##
  #############
  leafpal <- colorFactor(palette = rev("RdPu"), 
                         domain = egtrig$number)
  
  leafpal2 <- colorFactor(palette = rev("RdPu"), 
                         domain = egtrig$corer)
  
  if(max(egtrig$lon)-min(egtrig$lon) < 0.2 | max(egtrig$lat)-min(egtrig$lat) < 0.2){
    minlon<-min(egtrig$lon)+0.1
    minlat<-min(egtrig$lat)-0.1
    maxlon<-max(egtrig$lon)-0.1
    maxlat<-max(egtrig$lat)+0.1
  } else {
    minlon<-min(egtrig$lon)
    minlat<-min(egtrig$lat)
    maxlon<-max(egtrig$lon)
    maxlat<-max(egtrig$lat)
  }
  
  mapbase<-leaflet(data = egdaily, options = leafletOptions(zoomControl = FALSE)) %>% 
    addEsriBasemapLayer(esriBasemapLayers$Oceans, autoLabels=FALSE) %>%
    addPolygons(data = spm.sp, weight = 2, color = "white") %>%
    addPolylines(data = fath_10.sp, weight = 2, color = "orange")%>%
    addPolylines(data = fath_20.sp, weight = 2, color = "brown")%>%
    addPolygons(data = crit_habi.sp, weight = 2, color = "yellow")%>%
    fitBounds(minlon,minlat,maxlon,maxlat)
  
  if (FS == 'FISH'){
    mapbase<-mapbase%>%
      addPolygons(data = dynafish.sp, weight = 2, color = "black", fill = F) %>%
      addPolygons(data = ATL_grid.crop, weight = 2, color = "grey", fill = F, opacity = 0.2, label = ATL_grid.crop$Grid_Index, labelOptions = labelOptions(noHide = T, textOnly = TRUE, direction = "center"))
  } else {
    mapbase<-mapbase%>%
      addPolygons(data = dynaship.sp, weight = 3, color = "green", opacity = 0.8) %>%
      addPolylines(data = shipzone.sp, weight = 2, color = "red")%>%
      addWMSTiles(
        "https://gis.ngdc.noaa.gov/arcgis/services/graticule/MapServer/WMSServer/",
        layers = c("1-degree grid", "5-degree grid"),
        options = WMSTileOptions(format = "image/png8", transparent = TRUE),
        attribution = NULL)
  }
  
 map1<-mapbase%>%
   addCircleMarkers(lng = ~egtrig$lon, lat = ~egtrig$lat, radius = 5, fillOpacity = 1, weight = 2, color = "black", fillColor = ~leafpal(egtrig$number), popup = paste0(egtrig$time,", Group Size:", egtrig$number))%>%
   addLegend(pal = leafpal, values = egtrig$number, opacity = 0.9, position = "topleft", title = "# NARW / BNAN")
 
 map2<-mapbase%>%
   addPolygons(data = polycoorddf_sp, weight = 2, color = "black",fill = F)%>%
   addCircleMarkers(lng = ~egtrig$lon, lat = ~egtrig$lat, radius = 5, fillOpacity = 1, weight = 2, color = "black", fillColor = ~leafpal(egtrig$number), popup = paste0(egtrig$time,", Group Size:", egtrig$number))%>%
   addLegend(pal = leafpal2, values = egtrig$corer, opacity = 0.9, position = "topleft", title = "Whale Density Radius (nm)")

 map3<-mapbase%>%    
   addPolygons(data = polycoorddf_sp, weight = 2, color = "black",fill = F)%>%
   addPolygons(data = polyclust_sp, weight = 2, color = "blue")%>%
   addLegend(colors = c("blue"), labels = c("Core Area"), opacity = 0.3, position = "topleft")
 
 map4<-mapbase%>%
   addCircleMarkers(data = centroid, weight = 2, color = "red", fillOpacity = 1, radius = 5) %>%
   addPolygons(data = polyclust_sp, weight = 2, color = "blue")%>%
   addLegend(colors = c("red"), labels = "Calculated Center of Core Area", opacity = 0.9, position = "topleft")%>%
   addLegend(colors = c("blue"), labels = c("Core Area"), opacity = 0.3, position = "topleft")
   
snap(map1,1)
print("map 1")  
snap(map2,2)
print("map 2") 
snap(map3,3)
print("map 3") 
snap(map4,4) 
print("map 4")

output$map1<-renderLeaflet({map1})
output$map2<-renderLeaflet({map2})
output$map3<-renderLeaflet({map3})
output$map4<-renderLeaflet({map4})
enable("mappdf")
output$trigmessage<-renderText({})

incProgress(1/5) #for progress bar
}
  

  #########################
  #this section was used to make mapbase for the pdf output, but it does not need to be run every time. Only if shapes change. Go to line 409.
  #need to also uncomment the snap for mapb below 
  # mapb<-mapbase%>%
  #   addPolygons(data = ATL_grid.sp, weight = 2, color = "grey", fill = F, opacity = 0.1)%>%
  #   addLegend(colors = c("green","red","black","grey","yellow","white"), labels = c("Dynamic Shipping Section","Speed Restriction Zones","1 Whale Trigger Fishing Area","Full Fishing Grid","NARW Critical Habitat","SPM EEZ"), opacity = 0.3, position = "topleft")%>%
  #   addLegend(colors = c("orange","brown"), labels = c("10 fathom line", "20 fathom line"), opacity = 0.9, position = "topright")
  # 
  # #this section was used to output mapbase, but it does not need to be run everytime. Only need to run if something changes.
  # #should make this an if clause
  # snap(mapb,"ase")
  # print("mapb")
  ########################
  