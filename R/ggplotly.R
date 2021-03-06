##' Drawing ggplot2 geoms with a group aesthetic is most efficient in
##' plotly when we convert groups of things that look the same to
##' vectors with NA.
##' @param g list of geom info with g$data$group.
##' @param geom change g$geom to this.
##' @export
##' @return list of geom info.
##' @author Toby Dylan Hocking
group2NA <- function(g, geom){
  poly.list <- split(g$data, g$data$group)
  is.group <- names(g$data) == "group"
  poly.na.df <- data.frame()
  for(i in seq_along(poly.list)){
    no.group <- poly.list[[i]][,!is.group,drop=FALSE]
    na.row <- no.group[1,]
    na.row[,c("x", "y")] <- NA
    poly.na.df <- rbind(poly.na.df, no.group, na.row)
  }
  g$data <- poly.na.df
  g$geom <- geom
  g
}

#' Convert R pch point codes to plotly "symbol" codes.
pch2symbol <- c("0"="square",
                "1"="circle",
                "2"="triangle-up",
                "3"="cross",
                "4"="x",
                "5"="diamond",
                "6"="triangle-down",
                "15"="square",
                "16"="circle",
                "17"="triangle-up",
                "18"="diamond",
                "19"="circle",
                "20"="circle",
                "22"="square",
                "23"="diamond",
                "24"="triangle-up",
                "25"="triangle-down",
                "o"="circle",
                "O"="circle",
                "+"="cross")

#' Convert ggplot2 aes to plotly "marker" codes.
aes2marker <- c(alpha="opacity",
                colour="color",
                size="size",
                shape="symbol")

marker.defaults <- c(alpha=1,
                     shape="o",
                     size=1,
                     colour="black")
line.defaults <-
  list(linetype="solid",
       colour="black",
       size=2,
       direction="linear")

numeric.lty <-
  c("1"="solid",
    "2"="dash",
    "3"="dot",
    "4"="dashdot",
    "5"="longdash",
    "6"="longdashdot")

named.lty <-
  c("solid"="solid",
    "blank"="none",
    "dashed"="dash",
    "dotted"="dotted",
    "dotdash"="dashdot",
    "longdash"="longdash",
    "twodash"="dash")

## TODO: does plotly support this??
coded.lty <-
  c("22"="dash",
    "42"="dot",
    "44"="dashdot",
    "13"="longdash",
    "1343"="longdashdot",
    "73"="dash",
    "2262"="dotdash",
    "12223242"="dotdash",
    "F282"="dash",
    "F4448444"="dash",
    "224282F2"="dash",
    "F1"="dash")

#' Convert R lty line type codes to plotly "dash" codes.
lty2dash <- c(numeric.lty, named.lty, coded.lty)

aesConverters <-
  list(linetype=function(lty){
    lty2dash[as.character(lty)]
  },colour=function(col){
    toRGB(col)
  },size=identity,alpha=identity,shape=function(pch){
    pch2symbol[as.character(pch)]
  }, direction=identity)

toBasic <-
  list(segment=function(g){
    ## Every row is one segment, we convert to a line with several
    ## groups which can be efficiently drawn by adding NA rows.
    g$data$group <- 1:nrow(g$data)
    used <- c("x", "y", "xend", "yend")
    others <- g$data[!names(g$data) %in% used]
    g$data <- with(g$data, {
      rbind(cbind(x, y, others),
            cbind(x=xend, y=yend, others))
    })
    group2NA(g, "path")
  },polygon=function(g){
    if(is.null(g$params$fill)){
      g
    }else if(is.na(g$params$fill)){
      group2NA(g, "path")
    }else{
      g
    }
  },path=function(g){
    group2NA(g, "path")
  },line=function(g){
    g$data <- g$data[order(g$data$x),]
    group2NA(g, "path")
  },ribbon=function(g){
    stop("TODO")
  })

#' Convert basic geoms to traces.
geom2trace <-
  list(path=function(data, params){
    list(x=data$x,
         y=data$y,
         name=params$name,
         text=data$text,
         type="scatter",
         mode="lines",
         line=paramORdefault(params, aes2line, line.defaults))
  },polygon=function(data, params){
    list(x=c(data$x, data$x[1]),
         y=c(data$y, data$y[1]),
         name=params$name,
         text=data$text,
         type="scatter",
         mode="lines",
         line=paramORdefault(params, aes2line, line.defaults),
         fill="tonextx",
         fillcolor=toRGB(params$fill))
  },point=function(data, params){
    L <- list(x=data$x,
              y=data$y,
              name=params$name,
              text=data$text,
              type="scatter",
              mode="markers",
              marker=paramORdefault(params, aes2marker, marker.defaults))
    if("size" %in% names(data)){
      L$marker$sizeref <- min(data$size)
      L$marker$sizemode <- "area"
      L$marker$size <- data$size
    }
    L
  },
  bar=function(data, params) {
    list(x=data$x,
         y=(data$y - data$ymin),
         name=params$name,
         text=data$text,
         type="bar",
         fillcolor=toRGB(params$fill))
  },
  step=function(data, params) {
    list(x=data$x,
         y=data$y,
         name=params$name,
         type="scatter",
         mode="lines",
         line=paramORdefault(params, aes2line, line.defaults))
  }
  )


#' Convert ggplot2 aes to line parameters.
aes2line <- c(linetype="dash",
              colour="color",
              size="width",
              direction="shape")

markLegends <-
  list(point=c("colour", "fill", "shape"),
       path=c("linetype", "size", "colour"),
       polygon=c("colour", "fill", "linetype", "size", "group"),
       bar=c("fill"),
       step=c("linetype", "size", "colour"))

markUnique <- as.character(unique(unlist(markLegends)))

#' Convert a ggplot to a list.
#' @import ggplot2
#' @param p ggplot2 plot.
#' @return list representing a ggplot.
#' @export
gg2list <- function(p){
  if(length(p$layers) == 0) {
    stop("No layers in plot")
  }
  ## Always use identity size scale so that plot.ly gets the real
  ## units for the size variables.
  p <- tryCatch({
    ## this will be an error for discrete variables.
    suppressMessages({
      ggplot2::ggplot_build(p+scale_size_continuous())
      p+scale_size_identity()
    })
  },error=function(e){
    p
  })
  layout <- list()
  trace.list <- list()
  ## Before building the ggplot, we would like to add aes(name) to
  ## figure out what the object group is later. This also copies any
  ## needed global aes/data values to each layer, so we do not have to
  ## worry about combining global and layer-specific aes/data later.
  for(layer.i in seq_along(p$layers)){
    layer.aes <- p$layers[[layer.i]]$mapping
    to.copy <- names(p$mapping)[!names(p$mapping) %in% names(layer.aes)]
    layer.aes[to.copy] <- p$mapping[to.copy]
    mark.names <- markUnique[markUnique %in% names(layer.aes)]
    name.names <- sprintf("%s.name", mark.names)
    layer.aes[name.names] <- layer.aes[mark.names]
    p$layers[[layer.i]]$mapping <- layer.aes
    if(!is.data.frame(p$layers[[layer.i]]$data)){
      p$layers[[layer.i]]$data <- p$data
    }
  }
  geom_type <- p$layers[[layer.i]]$geom
  geom_type <- strsplit(capture.output(geom_type), "geom_")[[1]][2]
  geom_type <- strsplit(geom_type, ": ")[[1]]
  ## Barmode.
  layout$barmode <- "group"
  if (geom_type == "bar") {
    stat_type <- capture.output(p$layers[[layer.i]]$stat)
    stat_type <- strsplit(stat_type, ": ")[[1]]
    if (!grepl("identity", stat_type)) {
      stop("Conversion not implemented for ", stat_type)
    }
    pos <- capture.output(p$layers[[layer.i]]$position)
    if (grepl("identity", pos)) {
      layout$barmode <- "overlay"
    } else if (grepl("stack", pos)) {
      layout$barmode <- "stack"
    }
  }
  
  ## Extract data from built ggplots
  built <- ggplot2::ggplot_build(p)
  ranges <- built$panel$ranges[[1]]
  for(i in seq_along(built$plot$layers)){
    ## This is the layer from the original ggplot object.
    L <- p$layers[[i]]
    
    ## for each layer, there is a correpsonding data.frame which
    ## evaluates the aesthetic mapping.
    df <- built$data[[i]]
    
    ## Test fill and color to see if they encode a quantitative
    ## variable. This may be useful for several reasons: (1) it is
    ## sometimes possible to plot several different colors in the same
    ## trace (e.g. points), and that is faster for large numbers of
    ## data points and colors; (2) factors on x or y axes should be
    ## sent to plotly as characters, not as numeric data (which is
    ## what ggplot_build gives us).
    misc <- list()
    for(a in c("fill", "colour", "x", "y")){
      for(data.type in c("continuous", "date", "datetime", "discrete")){
        fun.name <- sprintf("scale_%s_%s", a, data.type)
        misc.name <- paste0("is.", data.type)
        misc[[misc.name]][[a]] <- tryCatch({
          fun <- get(fun.name)
          suppressMessages({
            with.scale <- p+fun()
          })
          ggplot2::ggplot_build(with.scale)
          TRUE
        }, error=function(e){
          FALSE
        })
      }
    }
    
    ## scales are needed for legend ordering.
    for(sc in p$scales$scales){
      a <- sc$aesthetics
      if(length(a) == 1){
        br <- sc$breaks
        ranks <- seq_along(br)
        names(ranks) <- br
        misc$breaks[[sc$aesthetics]] <- ranks
      }
    }
    
    ## This extracts essential info for this geom/layer.
    traces <- layer2traces(L, df, misc)
    
    ## Do we really need to coord_transform?
    ##g$data <- ggplot2:::coord_transform(built$plot$coord, g$data,
    ##                                     built$panel$ranges[[1]])
    trace.list <- c(trace.list, traces)
  }
  # Export axis specification as a combination of breaks and
  # labels, on the relevant axis scale (i.e. so that it can
  # be passed into d3 on the x axis scale instead of on the
  # grid 0-1 scale). This allows transformations to be used
  # out of the box, with no additional d3 coding.
  theme.pars <- ggplot2:::plot_theme(p)
  
  ## Flip labels if coords are flipped - transform does not take care
  ## of this. Do this BEFORE checking if it is blank or not, so that
  ## individual axes can be hidden appropriately, e.g. #1.
  ## ranges <- built$panel$ranges[[1]]
  ## if("flip"%in%attr(built$plot$coordinates, "class")){
  ##   temp <- built$plot$labels$x
  ##   built$plot$labels$x <- built$plot$labels$y
  ##   built$plot$labels$y <- temp
  ## }
  e <- function(el.name){
    ggplot2::calc_element(el.name, p$theme)
  }
  is.blank <- function(el.name){
    "element_blank"%in%attr(e(el.name),"class")
  }
  for(xy in c("x","y")){
    ax.list <- list()
    s <- function(tmp)sprintf(tmp, xy)
    ax.list$tickcolor <- toRGB(theme.pars$axis.ticks$colour)
    ax.list$gridcolor <- toRGB(theme.pars$panel.grid.major$colour)
    ## These numeric length variables are not easily convertible.
    ##ax.list$gridwidth <- as.numeric(theme.pars$panel.grid.major$size)
    ##ax.list$ticklen <- as.numeric(theme.pars$axis.ticks.length)
    ax.list$tickwidth <- theme.pars$axis.ticks$size
    tick.text.name <- s("axis.text.%s")
    ax.list$showticklabels <- ifelse(is.blank(tick.text.name), FALSE, TRUE)
    tick.text <- e(tick.text.name)
    ax.list$tickangle <- if(is.numeric(tick.text$angle)){
      -tick.text$angle
    }
    theme2font <- function(text){
      if(!is.null(text)){
        with(text, {
          list(family=family,
               size=size,
               color=toRGB(colour))
        })
      }
    }
    ## Translate axes labels.
    scale.i <- which(p$scales$find(xy))
    ax.list$title <- if(length(scale.i)){
      sc <- p$scales$scales[[scale.i]]
      if(!is.null(sc$name)){
        sc$name
      }else{
        p$labels[[xy]]
      }
    }else{
      p$labels[[xy]]
    }
    ax.list$tickfont <- theme2font(tick.text)
    title.text <- e(s("axis.title.%s"))
    ax.list$titlefont <- theme2font(title.text)
    ax.list$type <- if(misc$is.continuous[[xy]]){
      "linear"
    }else if(misc$is.discrete[[xy]]){
      "category"
    }else if(misc$is.date[[xy]] || misc$is.datetime[[xy]]){
      "date"
    }else{
      stop("unrecognized data type for ", xy, " axis")
    }
    ## Lines drawn around the plot border:
    ax.list$showline <- ifelse(is.blank("panel.border"), FALSE, TRUE)
    ax.list$linecolor <- toRGB(theme.pars$panel.border$colour)
    ax.list$linewidth <- theme.pars$panel.border$size
    ## Some other params that we used in animint but we don't yet
    ## translate to plotly:
    !is.blank(s("axis.line.%s"))
    !is.blank(s("axis.ticks.%s"))
    layout[[s("%saxis")]] <- ax.list
  }
  
  ## Remove legend if theme has no legend position
  if(theme.pars$legend.position=="none") layout$showlegend <- FALSE
  
  ## Main plot title.
  layout$title <- built$plot$labels$title
  
  ## Background color.
  layout$plot_bgcolor <- toRGB(theme.pars$panel.background$fill)
  layout$paper_bgcolor <- toRGB(theme.pars$plot.background$fill)
  
  ## Legend.
  layout$margin$r <- 10
  layout$legend <- list(bordercolor="transparent", x=100, y=1/2)
  
  trace.list$kwargs <- list(layout=layout)
  if(length(trace.list) == 1){
    stop("No exportable traces")
  }
  trace.list
}

#' Convert a layer to a list of traces. Called from gg2list()
#' @param l one layer of the ggplot object
#' @param d one layer of calculated data from ggplot2::ggplot_build(p)
#' @param misc named list.
#' @return list representing a layer, with corresponding aesthetics, ranges, and groups.
#' @export
layer2traces <- function(l, d, misc){
  g <- list(geom=l$geom$objname,
            data=d)
  ## needed for when group, etc. is an expression.
  g$aes <- sapply(l$mapping, function(k) as.character(as.expression(k)))

  ## For non-numeric data on the axes, we should take the values from
  ## the original data.
  for(axis.name in c("x", "y")){
    if(!misc$is.continuous[[axis.name]]){
      aes.names <- paste0(axis.name, c("", "end", "min", "max"))
      aes.used <- aes.names[aes.names %in% names(g$aes)]
      for(a in aes.used){
        col.name <- g$aes[aes.used]
        data.vec <- l$data[[col.name]]
        if(inherits(data.vec, "POSIXt")){
          data.vec <- strftime(data.vec, "%Y-%m-%d %H:%M:%S")
        }
        g$data[[a]] <- data.vec
      }
    }
  }
  ## use un-named parameters so that they will not be exported
  ## to JSON as a named object, since that causes problems with
  ## e.g. colour.
  g$params <- c(l$geom_params, l$stat_params)
  ## non-ggplot2 params like name are useful for plot.ly and ggplot2
  ## places them into stat_params.
  for(p.name in names(g$params)){
    ## c("foo") is translated to "foo" in JSON, so instead we use
    ## list("foo") which becomes ["foo"]. However we need to make sure
    ## that the list does not have names since list(bar="foo") becomes
    ## {"bar":"foo"}
    names(g$params[[p.name]]) <- NULL
  }
  
  ## Convert complex ggplot2 geoms so that they are treated as special
  ## cases of basic geoms. In ggplot2, this processing is done in the
  ## draw method of the geoms.
  
  ## Every plotly trace has one of these types
  ## type=scatter,bar,box,histogramx,histogram2d,heatmap
  
  ## for type=scatter, you can define
  ## mode=none,markers,lines,lines+markers where "lines" is the
  ## default for 20 or more points, "lines+markers" is the default for
  ## <20 points. "none" is useful mainly if fill is used to make area
  ## plots with no lines.
  
  ## marker=list(size,line,color="rgb(54,144,192)",opacity,symbol)
  
  ## symbol=circle,square,diamond,cross,x,
  ## triangle-up,triangle-down,triangle-left,triangle-right
  
  ## First convert to a "basic" geom, e.g. segments become lines.
  convert <- toBasic[[g$geom]]
  basic <- if(is.null(convert)){
    g
  }else{
    convert(g)
  }
  
  ## Then split on visual characteristics that will get different
  ## legend entries.
  data.list <- if(basic$geom %in% names(markLegends)){
    mark.names <- markLegends[[basic$geom]]
    ## However, continuously colored points are an exception: they do
    ## not need a legend entry, and they can be efficiently rendered
    ## using just 1 trace.
    
    ## Maybe it is nice to show a legend for continuous points?
    ## if(basic$geom == "point"){
    ##   to.erase <- names(misc$is.continuous)[misc$is.continuous]
    ##   mark.names <- mark.names[!mark.names %in% to.erase]
    ## }
    name.names <- sprintf("%s.name", mark.names)
    is.split <- names(basic$data) %in% name.names
    if(any(is.split)){
      data.i <- which(is.split)
      matched.names <- names(basic$data)[data.i]
      name.i <- which(name.names %in% matched.names)
      invariable.names <- cbind(name.names, mark.names)[name.i,]
      other.names <- !names(basic$data) %in% invariable.names
      vec.list <- basic$data[is.split]
      df.list <- split(basic$data, vec.list, drop=TRUE)
      lapply(df.list, function(df){
        params <- basic$params
        params[invariable.names] <- df[1, invariable.names]
        list(data=df[other.names],
             params=params)
      })
    }
  }
  ## case of no legend, if either of the two ifs above failed.
  if(is.null(data.list)){
    data.list <- structure(list(list(data=basic$data, params=basic$params)),
                           names=basic$params$name)
  }
  
  getTrace <- geom2trace[[basic$geom]]
  if(is.null(getTrace)){
    warning("Conversion not implemented for geom_",
            g$geom, " (basic geom_", basic$geom, "), ignoring. ",
            "Please open an issue with your example code at ",
            "https://github.com/ropensci/plotly/issues")
    return(list())
  }
  traces <- NULL
  for(data.i in seq_along(data.list)){
    data.params <- data.list[[data.i]]
    tr <- do.call(getTrace, data.params)
    for(v.name in c("x", "y")){
      vals <- tr[[v.name]]
      if(is.na(vals[length(vals)])){
        tr[[v.name]] <- vals[-length(vals)]
      }
    }
    name.names <- grep("[.]name$", names(data.params$params), value=TRUE)
    if(length(name.names)){
      for(a.name in name.names){
        a <- sub("[.]name$", "", a.name)
        a.value <- as.character(data.params$params[[a.name]])
        ranks <- misc$breaks[[a]]
        if(length(ranks)){
          tr$sort[[a.name]] <- ranks[[a.value]]
        }
      }
      name.list <- data.params$params[name.names]
      tr$name <- paste(unlist(name.list), collapse=".")
    }
    traces <- c(traces, list(tr))
  }
  sort.val <- sapply(traces, function(tr){
    rank.val <- unlist(tr$sort)
    if(is.null(rank.val)){
      0
    }else if(length(rank.val)==1){
      rank.val
    }else{
      0
    }
  })
  ord <- order(sort.val)
  no.sort <- traces[ord]
  for(tr.i in seq_along(no.sort)){
    no.sort[[tr.i]]$sort <- NULL
  }
  no.sort
}

##' convert ggplot params to plotly.
##' @param params named list ggplot names -> values.
##' @param aesVec vector mapping ggplot names to plotly names.
##' @param defaults named list ggplot names -> values.
##' @export
##' @return named list.
##' @author Toby Dylan Hocking
paramORdefault <- function(params, aesVec, defaults){
  marker <- list()
  for(ggplot.name in names(aesVec)){
    plotly.name <- aesVec[[ggplot.name]]
    ggplot.value <- params[[ggplot.name]]
    if(is.null(ggplot.value)){
      ggplot.value <- defaults[[ggplot.name]]
    }
    if(is.null(ggplot.value)){
      print(defaults)
      stop("no ggplot default for ", ggplot.name)
    }
    convert <- aesConverters[[ggplot.name]]
    if(is.null(convert)){
      stop("no ggplot converter for ", ggplot.name)
    }
    plotly.value <- convert(ggplot.value)
    names(plotly.value) <- NULL
    marker[[plotly.name]] <- plotly.value
  }
  marker
}

#' Convert R colors to RGB hexadecimal color values
#' @param x character
#' @return hexadecimal color value (if is.na(x), return "none" for compatibility with JavaScript)
#' @export
toRGB <- function(x){
  if(is.null(x))return(x)
  rgb.matrix <- col2rgb(x)
  rgb.text <- apply(rgb.matrix, 2, paste, collapse=",")
  rgb.css <- sprintf("rgb(%s)", rgb.text)
  ifelse(is.na(x), "none", rgb.css)
}

#' Convert R position to plotly barmode
position2barmode <- c("stack"="stack",
                      "dodge"="group",
                      "identity"="overlay")
