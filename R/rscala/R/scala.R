#' Instantiate a Scala Bridge
#'
#' This function creates an instance of a Scala bridge.  Details on this
#' function (and the rscala package as a whole) are provided in the package
#' vignette. The original paper was published in the \emph{Journal of Statistical
#' Software}. See the reference below.
#'
#' Multiple interpreters can be created and each runs independently with its own
#' memory space. Each interpreter can use multiple threads/cores, but the bridge
#' between \R and Scala is itself not thread-safe, so multiple \R threads/cores
#' should not simultaneously access the same bridge.
#'
#' Terminate the bridge using \code{\link{close.rscalaBridge}}.
#'
#' @param JARs Character vector describing JAR files to include in the
#'   classpath. Elements are some combination of file paths to JARs or package
#'   names which contain embedded JARs.  In the case of package names, the
#'   embedded JARs of all packages that recursively depend on, import, or
#'   suggest the specified package are also included.
#' @param serialize.output Logical indicating whether Scala output should be
#'   serialized back to R.  This is slower and probably only needed on Windows.
#' @param stdout When \code{serialize.output == FALSE}, this argument influences
#'   where "standard output" results should be sent.  \code{TRUE} or \code{""}
#'   sends output to the \R console (although that may not work on Windows).
#'   \code{FALSE} or \code{NULL} discards the output.  Otherwise, this is the
#'   name of the file that receives the output.
#' @param stderr Same as \code{stdout}, except influences the "standard error".
#' @param port If \code{0}, two random ports are selected.  Otherwise,
#'   \code{port} and \code{port+1} are used to the TCP/IP connections.
#' @param heap.maximum String giving Scala's heap maximum, e.g., "8G" or "512M".
#'   The value here supersedes that from \code{\link{scalaMemory}}. Without this
#'   being set by either \code{\link{scala}} or \code{\link{scalaMemory}}, the
#'   heap maximum will be 90\% of the available RAM.
#' @param command.line.arguments A character vector of extra command line
#'   arguments to pass to the Scala executable, where each element corresponds
#'   to one argument.
#' @param debug (Developer use only.)  Logical indicating whether debugging
#'   should be enabled.
#'
#' @return Returns a Scala bridge.
#' @references {David B. Dahl (2019). "Integration of R and Scala Using rscala."
#'   Journal of Statistical Software, 92:4, 1-18. https://www.jstatsoft.org}
#' @seealso \code{\link{close.rscalaBridge}}, \code{\link{scalaMemory}}
#'   \code{\link{scalaPushRegister}}, \code{\link{scalaPullRegister}}
#' @export
#' @importFrom tools dependsOnPkgs
#' @aliases rscala-package
#'
#' @examples \donttest{
#' s <- scala()
#' rng <- s $ .new_scala.util.Random()
#' rng $ alphanumeric() $ take(15L) $ mkString(',')
#' s * '2+3'
#' h <- s(x=2, y=3) ^ 'x+y'
#' h $ toString()
#' s(mean=h, sd=2, r=rng) * 'mean + sd * r.nextGaussian()'
#' close(s)
#' }
#'
scala <- function(JARs=character(),
                  serialize.output=.Platform$OS.type=="windows",
                  stdout=TRUE,
                  stderr=TRUE,
                  port=0L,
                  heap.maximum=NULL,
                  command.line.arguments=character(0),
                  debug=FALSE) {
  if ( missing(stdout) && ( Sys.getenv("RSCALA_STDOUT") != "" ) ) {
    x <- Sys.getenv("RSCALA_STDOUT")
    stdout <- if ( x %in% c("TRUE","FALSE") ) as.logical(x) else x
  }
  if ( identical(stdout,TRUE) ) stdout <- ""
  if ( missing(stderr) && ( Sys.getenv("RSCALA_STDERR") != "" ) ) {
    x <- Sys.getenv("RSCALA_STDERR")
    stderr <- if ( x %in% c("TRUE","FALSE") ) as.logical(x) else x
  }
  if ( identical(stderr,TRUE) ) stderr <- ""
  debug <- if ( missing(debug) && ( Sys.getenv("RSCALA_DEBUG") != "" ) ) {
     as.logical(Sys.getenv("RSCALA_DEBUG"))
  } else identical(debug,TRUE)
  serialize.output <- if ( missing(serialize.output) && ( Sys.getenv("RSCALA_SERIALIZE_OUTPUT") != "" ) ) {
     as.logical(Sys.getenv("RSCALA_SERIALIZE_OUTPUT"))
  } else identical(serialize.output,TRUE)
  port <- as.integer(port[1])
  if ( debug && serialize.output ) stop("When debug is TRUE, serialize.output must be FALSE.")
  if ( debug && ( identical(stdout,FALSE) || identical(stdout,NULL) || identical(stderr,FALSE) || identical(stderr,NULL) ) ) stop("When debug is TRUE, stdout and stderr must not be discarded.")
  details <- new.env(parent=emptyenv())
  transcompileHeader <- c("import org.ddahl.rscala.server.Transcompile._","import scala.util.control.Breaks")
  assign("transcompileHeader",transcompileHeader,envir=details)
  assign("transcompileSubstitute",list(),envir=details)
  sConfig <- tryCatch(scalaConfig(FALSE), error=function(e) list(error=e))
  if ( is.null(sConfig$error) ) {
    scalaMajor <- sConfig$scalaMajorVersion
    rscalaJARs <- list.files(system.file(file.path("java",paste0("scala-",scalaMajor)),package="rscala",mustWork=FALSE),".*\\.jar$",full.names=TRUE)
    if ( length(rscalaJARs) == 0 ) {
      sConfig$error <- list(message=paste0("\n\n<<<<<<<<<<\n<<<<<<<<<<\n<<<<<<<<<<\n\nScala version ",sConfig$scalaFullVersion," is not among the supported versions: ",paste(names(scalaVersionJARs()),collapse=", "),".\nPlease run 'rscala::scalaConfig(reconfig=TRUE)'\n\n>>>>>>>>>>\n>>>>>>>>>>\n>>>>>>>>>>\n"))
    } else {
      heap.maximum <- getHeapMaximum(heap.maximum,sConfig$javaArchitecture == 32)
      heap.maximum.argument <- if ( is.null(heap.maximum) ) NULL
      else shQuote(paste0("-J-Xmx",heap.maximum))
      command.line.arguments <- if ( is.null(command.line.arguments) || ( length(command.line.arguments) == 0 ) ) NULL
      else shQuote(command.line.arguments)
      sessionFilename <- tempfile("rscala-session-")
      writeLines(character(),sessionFilename)
      portsFilename <- tempfile("rscala-ports-")
      JARs <- unlist(lapply(JARs, function(x) {
        if ( identical(find.package(x,quiet=TRUE),character(0)) ) x
        else {
          newHeaders <- unlist(lapply(x,transcompileHeaderOfPackage))
          if ( length(newHeaders) > 0 ) {
            transcompileHeader <- c(get("transcompileHeader",envir=details), newHeaders)
            assign("transcompileHeader",transcompileHeader,envir=details)
          }
          newSubstitutes <- lapply(x,transcompileSubstituteOfPackage)
          if ( length(newSubstitutes) > 0 ) {
            transcompileSubstitute <- unlist(c(get("transcompileSubstitute",envir=details),newSubstitutes))
            assign("transcompileSubstitute",transcompileSubstitute,envir=details)
          }
          dependencies <- tools::dependsOnPkgs(x, dependencies=c("Depends", "Imports"))
          unlist(lapply(c(x,dependencies), function(y) jarsOfPackage(y,scalaMajor)))
        }
      }))
      if ( is.null(JARs) ) JARs <- character(0)
      JARs <- unique(path.expand(JARs))
      sapply(JARs, function(JAR) if ( ! file.exists(JAR) ) stop(paste0('File or package "',JAR,'" does not exist.')))
      rscalaClasspath <- shQuote(paste0(rscalaJARs,collapse=.Platform$path.sep))
      fullClasspath <- shQuote(paste0(c(rscalaJARs,JARs),collapse=.Platform$path.sep))
      args <- c(heap.maximum.argument,command.line.arguments,"-nc","-classpath",rscalaClasspath,"org.ddahl.rscala.server.Main",fullClasspath,port,portsFilename,sessionFilename,debug,serialize.output,FALSE)
      oldJavaEnv <- setJavaEnv(sConfig)
      if ( debug ) {
        cat(paste0("Cmd:  ",paste0(sConfig$scalaCmd,collapse=" | "),"\n"))
        cat(paste0("Args: ",paste0(args,collapse=" | "),"\n"))
      }
      system2(sConfig$scalaCmd,args,wait=FALSE,stdout=stdout,stderr=stderr)
      setJavaEnv(oldJavaEnv)
      assign("sessionFilename",sessionFilename,envir=details)
      assign("portsFilename",portsFilename,envir=details)
    }
  }
  assign("closed",FALSE,envir=details)
  assign("disconnected",TRUE,envir=details)
  assign("pidOfR",Sys.getpid(),envir=details)
  assign("interrupted",FALSE,envir=details)
  assign("debugTranscompilation",FALSE,envir=details)
  assign("debug",debug,envir=details)
  assign("serializeOutput",serialize.output,envir=details)
  assign("last",NULL,envir=details)
  assign("garbage",integer(),envir=details)
  assign("config",sConfig,envir=details)
  assign("heapMaximum",heap.maximum,envir=details)
  assign("JARs",JARs,envir=details)
  assign("pendingCallbacks",list(),envir=details)
  gcFunction <- function(e) {
    garbage <- details[["garbage"]]
    garbage[length(garbage)+1] <- e[["id"]]
    assign("garbage",garbage,envir=details)
  }
  assign("gcFunction",gcFunction,envir=details)
  reg.finalizer(details,close.rscalaBridge,onexit=TRUE)
  bridge <- mkBridge(details)
  assign("pushers",new.env(parent=emptyenv()),envir=details)
  assign("pullers",new.env(parent=emptyenv()),envir=details)
  scalaPushRegister(scalaPush.generic,"generic",bridge)
  scalaPushRegister(scalaPush.list,"list",bridge)
  scalaPushRegister(scalaPush.arrayOfMatrices,"arrayOfMatrices",bridge)
  scalaPullRegister(scalaPull.generic,"generic",bridge)
  scalaPullRegister(scalaPull.list,"list",bridge)
  scalaPullRegister(scalaPull.arrayOfMatrices,"arrayOfMatrices",bridge)
  bridge
}

mkBridge <- function(details) {
  bridge <- function(...) {
    bridge2 <- list(...)
    argnames <- names(bridge2)
    if ( is.null(argnames) ) {
      argnames <- sapply(substitute(list(...))[-1], deparse)
      names(bridge2) <- argnames
    } else {
      w <- argnames == ""
      if ( any(w) ) {
        argnames[w] <- sapply(substitute(list(...))[-1], deparse)[w]
        names(bridge2) <- argnames
      }
    }
    if( ( length(bridge2) > 0 )  && ( is.null(argnames) || ! all(grepl("^[a-zA-Z]\\w*$",argnames,perl=TRUE)) ) ) {
      stop("Every argument must be a named (e.g, x=3) or a symbol (e.g., x) and not a literal (e.g., 3).")
    }
    attr(bridge2,"details") <- details
    class(bridge2) <- "rscalaBridge"
    bridge2
  }
  attr(bridge,"details") <- details
  class(bridge) <- "rscalaBridge"
  bridge
}

embeddedR <- function(ports,debug=FALSE) {
  details <- new.env(parent=emptyenv())
  assign("config",list(),envir=details)
  assign("serializeOutput",FALSE,envir=details)
  assign("debug",debug,envir=details)
  assign("socketInPort",ports[1],envir=details)
  assign("socketOutPort",ports[2],envir=details)
  assign("pendingCallbacks",character(0),envir=details)
  scalaConnect(details)
  pop(details,NULL,.GlobalEnv)
}

scalaConnect <- function(details) {
  if ( ! is.null(details[["config"]]$error) ) stop(toString(details[["config"]]$error))
  if ( ! exists("socketInPort",envir=details) ) {
    portsFilename <- get("portsFilename",envir=details)
    ports <- local({
      delay <- 0.01
      while ( TRUE ) {
        if ( file.exists(portsFilename) ) {
          line <- scan(portsFilename,n=3L,what=character(),quiet=TRUE)
          if ( length(line) > 0 ) return(as.numeric(line))
        }
        Sys.sleep(delay)
      }
    })
    unlink(portsFilename)
    rm("portsFilename",envir=details)
    assign("socketInPort",ports[1],envir=details)
    assign("socketOutPort",ports[2],envir=details)
    assign("pidOfScala",ports[3],envir=details)
  }
  socketIn  <- socketConnection(host="localhost", port=details[['socketInPort']],  server=FALSE, blocking=TRUE, open="rb", timeout=2678400L)
  socketOut <- socketConnection(host="localhost", port=details[['socketOutPort']], server=FALSE, blocking=TRUE, open="ab", timeout=2678400L)
  attr(socketIn, "pidOfScala") <- details[['pidOfScala']]
  assign("socketIn",socketIn,envir=details)
  assign("socketOut",socketOut,envir=details)
  assign("disconnected",FALSE,envir=details)
  pendingCallbacks <- get("pendingCallbacks",envir=details)
  if ( length(pendingCallbacks) > 0 ) {
    scalaLazy(pendingCallbacks, details)
    assign("pendingCallbacks",list(),envir=details)
  }
  invisible()
}

osType <- function() {
  if ( .Platform$OS.type == "windows" ) "windows"
  else {
    sysname <- Sys.info()["sysname"]
    if ( sysname == "Darwin" ) "mac"
    else if ( sysname == "Linux" ) "linux"
    else ""
  }
}

getHeapMaximum <- function(heap.maximum,is32bit) {
  if ( ! is.null(heap.maximum) ) return(heap.maximum)
  heap.maximum <- getOption("rscala.heap.maximum")
  if ( ! is.null(heap.maximum) ) return(heap.maximum)
  memoryPercentage <- 0.90
  os <- osType()
  bytes <- if ( os == "linux" ) {
    outTemp <- readLines("/proc/meminfo")
    outTemp <- outTemp[grepl("^MemAvailable:\\s*",outTemp)]
    outTemp <- gsub("^MemAvailable:\\s*","",outTemp)
    outTemp <- gsub("\\s*kB$","",outTemp)
    as.numeric(outTemp) * 1024
  } else if ( os == "windows" ) {
    tryCatch({
      outTemp <- system2("wmic",c("/locale:ms_409","OS","get","FreePhysicalMemory","/VALUE"),stdout=TRUE,stderr=TRUE)
      outTemp <- outTemp[outTemp != "\r"]
      outTemp <- gsub("^FreePhysicalMemory=","",outTemp)
      outTemp <- gsub("\r","",outTemp)
      as.numeric(outTemp) * 1024
    }, error=function(x) NA, warning=function(x) NA)
  } else if ( os == "mac" ) {
    outTemp <- system2("vm_stat",stdout=TRUE,stderr=TRUE)
    outTemp <- outTemp[grepl("(Pages free|Pages inactive|Pages speculative):.*",outTemp)]
    sum(sapply(strsplit(outTemp,":"),function(x) as.numeric(x[2]))) * 4096
  } else NA                                       # Unknown, so do not do anything.
  if ( ! any(is.na(bytes)) ) {
    if ( is32bit ) bytes <- min(c(1.35*1024^3,bytes))   # 32 binaries have limited memory.
    paste0(max(32,as.integer(memoryPercentage * (bytes / 1024^2))),"M")  # At least 32M
  } else NULL
}

jarsOfPackage <- function(pkgname, major.release) {
  dir <- if ( file.exists(system.file("inst",package=pkgname)) ) file.path("inst/java") else "java"
  jarsMajor <- list.files(file.path(system.file(dir,package=pkgname),paste0("scala-",major.release)),pattern=".*\\.jar$",full.names=TRUE,recursive=FALSE)
  jarsAny <- list.files(system.file(dir,package=pkgname),pattern=".*\\.jar$",full.names=TRUE,recursive=FALSE)
  result <- normalizePath(c(jarsMajor,jarsAny))
  if ( length(result) == 0 ) {
    supported.versions <- list.files(system.file(dir,package=pkgname),pattern="scala-.*",full.names=FALSE,recursive=FALSE)
    recommended.version <- pickLatestStableScalaVersion(sub("^scala-","",supported.versions))
    stop(paste0("It appears that package '",pkgname,"' does not support Scala ",major.release,".  Hint, run:\n\n  Sys.setenv(RSCALA_SCALA_VERSION='",recommended.version,"'); rscala::scalaConfig(download='scala')\n\n  Then restart your R session and try again.\n"))
  }
  result
}

#' @importFrom utils getFromNamespace
#' 
transcompileHeaderOfPackage <- function(pkgname) {
  tryCatch( getFromNamespace("rscalaTranscompileHeader", pkgname), error=function(e) NULL )
}

#' @importFrom utils getFromNamespace
#' 
transcompileSubstituteOfPackage <- function(pkgname) {
  tryCatch( getFromNamespace("rscalaTranscompileSubstitute", pkgname), error=function(e) NULL )
}
