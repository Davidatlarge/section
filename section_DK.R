#### function to draw a section of interpolated data along a transect
# accepts vectors of corresponding lon, lat, depth, and data values
# accepts the input of bathymetry data as class "bathy", or creates bathymetry
# requires selection of distance, longitude or latitude as x values
# requires selection of a dominant section orientation towards N, E, S or W
# requires the following packages to be installed: "sp", "marmap", "reshape2", "MBA", and "ggplot2"
# value is a list containing a ggplot of the sections with interpolated data and bathymetry profile
#  and three data frames containing the interpolated data, the bathymetry profile, and the input data with section distance [km] added, respectively.
#  The list objects are named "plot", "output", "profile", and "input", respectively.
# created by David Kaiser; david.kaiser.82@gmail.com
#### in preparation:
# label contour lines

section.DK <- function(
  longitude, # vector of latitude in degrees north
  latitude, # vector of longitude in degrees east
  parameter, # verctor of values of parameter z to be plotted as color. accepts NAs but all Lon-Lat-Depth-Parameter combinations with parameters NA will be removed
  depth, # vector of depth values in m, negative numbers are accepted but will be converted to positives
  xy.ratio = NULL, # optional integer vector of length 2 in which first and second integers indicate the relative strength of interpolation in x and y direction, defaults to NULL and calculates the requred values according to mean depth resolution and distance between stations
  section.x = "km", # unit for x axis of the section. Options are "km" (the default), "degE", and "degN".
  section.direction = NA, # optional sorting of data by stations along a dominant direction. Options are "N", "E", "S", and "W", e.g. "S" creates a section running from north to south. Only really important if section.x = "km". If nothing is input, data verctors will not be resorted
  bathymetry = NULL, # optional bathymetry of class "bathy", if not supplied will be retrieved from NOAA for the domain of "longitude" and "latitude"
  max.depth = "profile", # select the section's maximum depth in bathymetry ("profile", the default) or in data ("data") as the maximum depth of the plot
  contour.breaks = 5 # either an integer defining the number of contour bins (defaults arbitrarily to 5), or a vector of values for the contour lines. To draw no contours "0" works but prints an error, NA does not work, NULL reverts to geom_stat default.
)
{
  require(sp)
  require(marmap)
  require(reshape2)
  require(MBA)
  require(ggplot2)
  
  #### data prep
  data <- data.frame(longitude, 
                     latitude, 
                     parameter,
                     depth)
  data$depth <- abs(data$depth)
  data <- subset(data, !is.na(data$parameter))
  
  stations <- data.frame(longitude, latitude)
  stations <- unique(stations)
  
  #### calculate section distance in the specified direction
  switch(section.direction, # evaluates which direction was supplied and returns the matching named element (like so many if() functions)
         "N" = stations <- stations[order(stations$latitude, decreasing = FALSE),], # sorts stations south to north
         "S" = stations <- stations[order(stations$latitude, decreasing = TRUE),], # sorts stations north to south
         "W" = stations <- stations[order(stations$longitude, decreasing = TRUE),], # sorts stations east to west
         "E" = stations <- stations[order(stations$longitude, decreasing = FALSE),] # sorts stations west to east
  )
  stations$section.dist.km <- spDistsN1(as.matrix(stations), as.numeric(stations[1,]), longlat = TRUE) # calculates distance in km from northernmost station
  data <- merge(data, stations, by = c("longitude","latitude"))
  
  #### construct section bathymetry profile if not supplied by user
  if(is.null(bathymetry)) {
    bathymetry <- getNOAA.bathy(lon1 = min(stations$longitude)-1,
                                lon2 = max(stations$longitude)+1,
                                lat1 = min(stations$latitude)-1,
                                lat2 = max(stations$latitude)+1, 
                                resolution = 1, keep = FALSE)
  }
  
  #### extract a bathymetry profile for the section
  profile <- path.profile(subset(stations, select = c(longitude, latitude)), bathymetry)
  profile$depth <- abs(profile$depth) # make the depth values positive
  
  #### defining values for interpolation strength in x and y directions
  if(is.null(xy.ratio)) {
    xres <- (max(data$section.dist.km)-min(data$section.dist.km)) / # gives the range between stations
      (sum(!is.na(unique(data$section.dist.km)))-1) # gives the number of steps between stations
    yres <- (max(data$depth)-min(data$depth)) / # gives the range of depth values
      (sum(!is.na(unique(data$depth)))-1) # gives the number of steps between depths
  }
  if(!is.null(xy.ratio)){
    xres <- xy.ratio[1]
    yres <- xy.ratio[2]
  }
  if(xres>yres) {
    n <- xres/yres
    m <- 1
  }
  if(xres<yres) {
    n <- 1
    m <- yres/xres
  }
  
  #### change the name of the column used for x to "section.x" for further handling
  switch(section.x,
         "km" = {
           names(data)[names(data)=="section.dist.km"] <- "section.x"
           names(stations)[names(stations)=="section.dist.km"] <- "section.x"
           names(profile)[names(profile)=="dist.km"] <- "section.x"
         },
         "degE" = {
           names(data)[names(data)=="longitude"] <- "section.x"
           names(stations)[names(stations)=="longitude"] <- "section.x"
           names(profile)[names(profile)=="lon"] <- "section.x"
         },
         "degN" = {
           names(data)[names(data)=="latitude"] <- "section.x"
           names(stations)[names(stations)=="latitude"] <- "section.x"
           names(profile)[names(profile)=="lat"] <- "section.x"
         }
  )
  
  #### interpolate data
  data <- data[order(data$section.x),] # orders rows by section.x 
  mba <- mba.surf(data[,c("section.x", "depth", "parameter")],  # xyz, where z is the parameter to be interpolated between x and y
                  no.X = 300, # x-resolution = number of points created over entire x, not per unit x
                  no.Y = 300, # same as for x
                  n = n, 
                  m = m, 
                  extend = TRUE)
  dimnames(mba$xyz.est$z) <- list(mba$xyz.est$x, mba$xyz.est$y)
  df.int <- melt(mba$xyz.est$z, varnames = c("section.x", "depth"), value.name = "parameter")
  
  #### calculate contour breaks if only one number is supplied
  if(length(contour.breaks)==1){
    contour.breaks <- seq(min(df.int$parameter, na.rm = TRUE), 
                          max(df.int$parameter, na.rm = TRUE), length.out = contour.breaks)
  }
  
  #### set max depth
  switch(max.depth,
         "data" = maxdepth <- max(df.int$depth, na.rm = TRUE),
         "profile" = maxdepth <- max(profile$depth, na.rm = TRUE)
         )
  
  #### plot section
  p1 <- ggplot()+
    geom_raster(data = df.int, 
                aes(section.x, depth, fill = parameter), 
                interpolate = FALSE) +
    geom_contour(data = df.int, 
                 aes(section.x, depth, z = parameter), 
                 col = "black", linetype = "dashed", size = 0.5, breaks = contour.breaks) + 
    scale_y_reverse(expand = c(0,0),  
                    name = "depth [m]",
                    limits = c(maxdepth, min(df.int$depth))) +
    geom_ribbon(data = profile, 
                aes(section.x, ymin = depth, ymax = maxdepth), 
                fill = "grey75") +
    geom_path(data = profile, 
              aes(section.x, depth), 
              col = "grey10") +  
    geom_point(data = stations, 
               aes(section.x, min(df.int$depth)), 
               size = 3, shape = 25, fill = "black") +
    scale_fill_gradientn(colours = c("blue", "green", "yellow", "red"), na.value = "transparent",
                         name = deparse(substitute(parameter))) + # adds the name of the originally supplied vector
    scale_x_continuous(expand = c(0,0)) +
    theme_classic()
  switch(section.x, # set x axis label according to its unit
         "km" = p1 <- p1 + xlab("section distance [km]"),
         "degE" = p1 <- p1 + xlab("longitude [°E]"),
         "degN" = p1 <- p1 + xlab("latidutde [°N]")
         )
  return(setNames(list(p1, df.int, profile, data), 
                  c("plot", "output", "profile", "input")))
  
}
