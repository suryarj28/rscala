#' Configure Scala and Java
#'
#' This function installs Scala and/or Java in the user's \code{~/.rscala}
#' directory.
#'
#' @param verbose Should details of the search for Scala and Java be provided?
#'   Or, if a Scala bridge is provided instead of a logical, the function
#'   returns a list of details associated with the supplied bridge.
#' @param reconfig If \code{TRUE}, the script \code{~/.rscala/config.R} is
#'   rewritten based on a new search for Scala and Java.  If \code{FALSE}, the
#'   previous configuration is sourced from the script
#'   \code{~/.rscala/config.R}.  If \code{"live"}, a new search is performed,
#'   but the results do not overwrite the previous configuration script.
#'   \code{"offline"} is the same as \code{"live"}, except no software is ever
#'   downloaded.
#'   Finally, the value set here is superceded by the value of the environment
#'   variable \code{RSCALA_RECONFIG}, if it exists.
#' @param download A character vector which may be length-zero or whose elements
#'   are any combination of \code{"java"}, \code{"scala"}, or \code{"sbt"}. Or,
#'   \code{TRUE} denotes all three.  The indicated software will be installed in
#'   "~/.rscala".
#' @param require.sbt Should SBT be required, downloading and installing it in
#'   '~/.rscala/sbt' if necessary?
#'
#' @return Returns a list of details of the Scala and Java binaries.
#' @references {David B. Dahl (2019). "Integration of R and Scala Using rscala."
#'   Journal of Statistical Software, 92:4, 1-18. https://www.jstatsoft.org}
#' @export
#' @examples \donttest{
#' scalaConfig()
#' }
#' 
scalaConfig <- function(verbose=TRUE, reconfig=FALSE, download=character(0), require.sbt=FALSE) {
  if ( inherits(verbose,"rscalaBridge") ) return(attr(verbose,"details")$config)
  if ( isTRUE(download) ) download <- c("java","scala","sbt")
  if ( length(setdiff(download,c("java","scala","sbt"))) > 0 ) stop('Invalid element in "download" argument.')
  download <- tolower(download)
  download.java <- "java" %in% download
  download.scala <- "scala" %in% download
  download.sbt <- "sbt" %in% download
  if ( Sys.getenv("RSCALA_RECONFIG") != "" ) reconfig <- Sys.getenv("RSCALA_RECONFIG")
  if ( reconfig %in% c("TRUE","FALSE") ) reconfig <- as.logical(reconfig)
  else if ( ! ( reconfig %in% c("live","offline") ) ) stop("'reconfig' is misspecified.")
  consent <- identical(reconfig,TRUE) || download.java || download.scala || download.sbt
  installPath <- path.expand(if ( Sys.getenv("RSCALA_HOME") != "" ) Sys.getenv("RSCALA_HOME") else file.path("~",".rscala"))
  dependsPath <- if ( identical(Sys.getenv("R_INSTALL_PKG"),"rscala") ) file.path(Sys.getenv("R_PACKAGE_DIR"),"dependencies") else ""
  offerInstall <- function(msg) {
    if ( ! ( reconfig %in% c("live","offline") ) && interactive() ) {
      while ( TRUE ) {
        cat(msg,"\n")
        response <- toupper(trimws(readline(prompt=paste0("Do you want to install here: ",installPath,"?  [Y/n] "))))
        if ( response == "N" ) return(FALSE)
        if ( response %in% c("Y","") ) return(TRUE)
      }
    } else FALSE
  }
  configPath <- file.path(installPath,"config.R")
  if ( file.exists(configPath) && ! consent && reconfig == FALSE) {
    if ( verbose ) cat(paste0("\nRead configuration file from rscala home: ",configPath,"\n\n"))
    source(configPath,chdir=TRUE,local=TRUE)
    if ( isConfigBroken(config, require.sbt) ) {
      if ( verbose ) cat("The configuration is out-of-date.  Reconfiguring...\n")
      unlink(configPath)
      scalaConfig(verbose, reconfig, download, require.sbt)
    } else config
  } else {
    tmpdir <- file.path(tempdir(),"rscala")
    if ( download.java ) installSoftware(installPath,"java",verbose=verbose)
    javaConf <- findExecutable("java","Java",installPath,javaSpecifics,verbose)
    stopMsg <- "\n\n<<<<<<<<<<\n<<<<<<<<<<\n<<<<<<<<<<\n\nJava is not found!  Please run 'rscala::scalaConfig(download=\"java\")'\n\n>>>>>>>>>>\n>>>>>>>>>>\n>>>>>>>>>>\n"
    if ( is.null(javaConf) ) {
      if ( download.java ) stop(stopMsg)
      if ( verbose ) cat("\n")
      if ( ! ( reconfig %in% c("live","offline") ) && interactive() ) {
        if ( ! ( consent || offerInstall("Java is not found.") ) ) stop(stopMsg)
        consent <- TRUE
        installSoftware(installPath,"java",verbose=verbose)
        javaConf <- findExecutable("java","Java",installPath,javaSpecifics,verbose)
        if ( is.null(javaConf) ) stop(stopMsg)
      } else {
        if ( reconfig == "offline" ) {
          stop(stopMsg)
        } else {
          if ( dependsPath != "" ) {
            installSoftware(dependsPath,"java",verbose=verbose)
            javaConf <- findExecutable("java","Java",installPath,javaSpecifics,verbose)
            if ( is.null(javaConf) ) stop(stopMsg)
          } else {
            installSoftware(tmpdir,"java",verbose=verbose)
            javaConf <- findExecutable("java","Java",installPath,javaSpecifics,verbose)
            if ( is.null(javaConf) ) stop(stopMsg)
            stopMsg <- "<<<<<<<<<<\n<<<<<<<<<<\n<<<<<<<<<<\n\nJava was downloaded to a temporary directory.  To make permanent, please run 'rscala::scalaConfig(download=\"java\")'\n\n>>>>>>>>>>\n>>>>>>>>>>\n>>>>>>>>>>\n"
            cat(stopMsg)
          }
        }
      }
    }
    if ( download.scala ) installSoftware(installPath,"scala",verbose=verbose)
    scalaSpecifics2 <- function(x,y) scalaSpecifics(x,javaConf,y)
    scalaConf <- findExecutable("scala","Scala",installPath,scalaSpecifics2,verbose)
    stopMsg <- "\n\n<<<<<<<<<<\n<<<<<<<<<<\n<<<<<<<<<<\n\nScala is not found!  Please run 'rscala::scalaConfig(download=\"scala\")'\n\n>>>>>>>>>>\n>>>>>>>>>>\n>>>>>>>>>>\n"
    if ( is.null(scalaConf) ) {
      if ( download.scala ) stop(stopMsg)
      if ( verbose ) cat("\n")
      if ( ! ( reconfig %in% c("live","offline") ) && interactive() ) {
        if ( ! ( consent || offerInstall("Scala is not found.") ) ) stop(stopMsg)
        consent <- TRUE
        installSoftware(installPath,"scala",verbose=verbose)
        scalaConf <- findExecutable("scala","Scala",installPath,scalaSpecifics2,verbose)
        if ( is.null(scalaConf) ) stop(stopMsg)
      } else {
        if ( reconfig == "offline" ) {
          stop(stopMsg)
        } else {
          if ( dependsPath != "" ) {
            installSoftware(dependsPath,"scala",verbose=verbose)
            scalaConf <- findExecutable("scala","Scala",installPath,scalaSpecifics2,verbose)
            if ( is.null(scalaConf) ) stop(stopMsg)
          } else {
            installSoftware(tmpdir,"scala",verbose=verbose)
            scalaConf <- findExecutable("scala","Scala",installPath,scalaSpecifics2,verbose)
            if ( is.null(scalaConf) ) stop(stopMsg)
            stopMsg <- "<<<<<<<<<<\n<<<<<<<<<<\n<<<<<<<<<<\n\nScala was downloaded to a temporary directory.  To make permanent, please run 'rscala::scalaConfig(download=\"scala\")'\n\n>>>>>>>>>>\n>>>>>>>>>>\n>>>>>>>>>>\n"
            cat(stopMsg)
          }
        }
      }
    }
    config <- c(format=4L,scalaConf,javaConf)
    if ( download.sbt ) installSoftware(installPath,"sbt",verbose=verbose)
    sbtSpecifics <- function(x,y) list(sbtCmd=x)
    sbtConf <- findExecutable("sbt","SBT",installPath,sbtSpecifics,verbose)
    stopMsg <- "\n\n<<<<<<<<<<\n<<<<<<<<<<\n<<<<<<<<<<\n\nSBT is not found!  Please run 'rscala::scalaConfig(download=\"sbt\")'\n\n>>>>>>>>>>\n>>>>>>>>>>\n>>>>>>>>>>\n"
    if ( is.null(sbtConf) && require.sbt ) {
      if ( download.sbt ) stop(stopMsg)
      if ( verbose ) cat("\n")
      if ( ! ( reconfig %in% c("live","offline") ) && interactive() ) {
        if ( ! ( consent || offerInstall("SBT is not found.") ) ) stop(stopMsg)
        consent <- TRUE
        installSoftware(installPath,"sbt",verbose=verbose)
        sbtConf <- findExecutable("sbt","SBT",installPath,sbtSpecifics,verbose)
        if ( is.null(sbtConf) ) stop(stopMsg)
      } else {
        if ( reconfig == "offline" ) {
          stop(stopMsg)
        } else {
          if ( dependsPath != "" ) {
            installSoftware(dependsPath,"sbt",verbose=verbose)
            sbtConf <- findExecutable("sbt","SBT",installPath,sbtSpecifics,verbose)
            if ( is.null(sbtConf) ) stop(stopMsg)          
          } else {
            installSoftware(tmpdir,"sbt",verbose=verbose)
            sbtConf <- findExecutable("sbt","SBT",installPath,sbtSpecifics,verbose)
            if ( is.null(sbtConf) ) stop(stopMsg)
            stopMsg <- "<<<<<<<<<<\n<<<<<<<<<<\n<<<<<<<<<<\n\nSBT was downloaded to a temporary directory.  To make permanent, please run 'rscala::scalaConfig(download=\"sbt\")'\n\n>>>>>>>>>>\n>>>>>>>>>>\n>>>>>>>>>>\n"
            cat(stopMsg)
          }
        }
      }
    }
    config <- c(config,sbtConf)
    if ( !consent && verbose ) cat("\n")
    writeConfig <- consent || offerInstall(paste0("Configuration file is not found (or is out-of-date)."))
    if ( writeConfig ) writeConfigFile(configPath, config, verbose)
    else if ( verbose ) cat("\n")
    config
  }
}

isConfigBroken <- function(config, require.sbt) {
  result <- try(silent=TRUE,
    ( is.null(config$format) || ( config$format < 4L ) || ( ! all(file.exists(c(config$javaHome,config$scalaHome,config$javaCmd,config$scalaCmd))) ) || ( is.null(config$sbtCmd) && require.sbt ) || ( ! is.null(config$sbtCmd) && ! file.exists(config$sbtCmd) ) )
  )
  inherits(result,"try-error") || result
}

writeConfigFile <- function(configPath, config, verbose) {
  installPath <- dirname(configPath)
  dir.create(installPath,showWarnings=FALSE,recursive=TRUE)
  outFile <- file(configPath,open="w")
  dump("config",file=outFile)
  close(outFile)
  if ( verbose ) cat(paste0("\nWrote configuration file: ",configPath,"\n\n"))
}

findExecutable <- function(mode,prettyMode,installPath,mapper,verbose=TRUE) {
  tryCandidate <- function(candidate) {
    if ( ! is.null(candidate) && length(candidate) == 1 && candidate != "" && file.exists(candidate) ) {
      if ( verbose ) cat(paste0("  Success with ",label,".\n"))
      result <- mapper(candidate,verbose)
      if ( is.character(result) ) {
        if ( verbose ) cat(paste0("  ... but ",result,"\n"))
        NULL
      } else result
    } else {
      if ( verbose ) cat(paste0("  Failure with ",label,".\n"))
      NULL
    }
  }
  allCaps <- toupper(mode)
  if ( verbose ) cat(paste0("\nSearching the system for ",prettyMode,".\n"))
  ###
  label <- "rscala home directory"
  regex <- sprintf("%s%s$",mode,if ( .Platform$OS.type == "windows" ) "(\\.exe|\\.bat)" else "")
  candidates <- list.files(installPath,paste0("^",regex),recursive=TRUE)
  candidates <- candidates[grepl(sprintf("^%s/(.*/|)bin/%s",mode,regex),candidates)]
  if ( length(candidates) > 1 ) candidates <- candidates[which.min(nchar(candidates))]
  conf <- tryCandidate(file.path(installPath,candidates))
  if ( ! is.null(conf) ) return(conf)
  ###
  label <- paste0(allCaps,"CMD environment variable")
  conf <- tryCandidate(Sys.getenv(paste0(allCaps,"CMD")))
  if ( ! is.null(conf) ) return(conf)
  ###
  label <- paste0(allCaps,"_HOME environment variable")
  home <- Sys.getenv(paste0(allCaps,"_HOME"))
  conf <- tryCandidate(if ( home != "" ) file.path(home,"bin",mode) else "")
  if ( ! is.null(conf) ) return(conf)
  ###
  if ( ( mode == "java" ) && ( osType() == "mac" ) ) {  # Avoid "No Java runtime present, requesting install." pop-up.
    label <- "/usr/libexec/java_home helper"
    home <- try(suppressWarnings(system2("/usr/libexec/java_home",stdout=TRUE,stderr=TRUE)),silent=TRUE)
    conf <- tryCandidate(if ( ! inherits(home,"try-error") && ( home != "" ) ) file.path(home,"bin",mode) else "")
    if ( ! is.null(conf) ) return(conf)
  } else {
    ###
    label <- "PATH environment variable"
    conf <- tryCandidate(Sys.which(mode)[[mode]])
    if ( ! is.null(conf) ) return(conf)
    ###
    if ( mode == "java" ) {
      label <- paste0("R CMD config JAVA")
      path <- tryCatch(system2(file.path(R.home("bin"),"R"),c("CMD","config","JAVA"),stdout=TRUE,stderr=FALSE), warning=function(e) NULL, error=function(e) NULL)
      conf <- tryCandidate(path)
      if ( ! is.null(conf) ) return(conf)
    }
  }
  ###
  label <- "rscala package directory"
  regex <- sprintf("%s%s$",mode,if ( .Platform$OS.type == "windows" ) "(\\.exe|\\.bat)" else "")
  pkgDir <- if ( identical(Sys.getenv("R_INSTALL_PKG"),"rscala") ) Sys.getenv("R_PACKAGE_DIR") else system.file(package="rscala")
  dependsPath <- file.path(pkgDir,"dependencies")
  candidates <- list.files(dependsPath,paste0("^",regex),recursive=TRUE)
  candidates <- candidates[grepl(sprintf("^%s/(.*/|)bin/%s",mode,regex),candidates)]
  if ( length(candidates) > 1 ) candidates <- candidates[which.min(nchar(candidates))]
  conf <- tryCandidate(file.path(dependsPath,candidates))
  if ( ! is.null(conf) ) return(conf)
  ###
  label <- "rscala temporary directory"
  regex <- sprintf("%s%s$",mode,if ( .Platform$OS.type == "windows" ) "(\\.exe|\\.bat)" else "")
  installPath <- file.path(tempdir(),"rscala")
  candidates <- list.files(installPath,paste0("^",regex),recursive=TRUE)
  candidates <- candidates[grepl(sprintf("^%s/(.*/|)bin/%s",mode,regex),candidates)]
  if ( length(candidates) > 1 ) candidates <- candidates[which.min(nchar(candidates))]
  conf <- tryCandidate(file.path(installPath,candidates))
  if ( ! is.null(conf) ) return(conf)
  NULL
}

endsWith <- function(string, appendix) {
  if ( nchar(appendix) == 0 ) TRUE
  else substr(string,nchar(string)-nchar(appendix)+1,nchar(string)) == appendix
}

extractArchive <- function(archivePath, parentDirectory, directoryName) {
  tmpInstallDirectory <- file.path(parentDirectory, paste0("tmp-", directoryName))
  if ( file.exists(tmpInstallDirectory) ) unlink(tmpInstallDirectory, TRUE, TRUE)
  dir.create(tmpInstallDirectory, showWarnings=FALSE)
  if ( endsWith(archivePath,".zip") ) utils::unzip(archivePath, exdir=tmpInstallDirectory, unzip="internal")
  else if ( endsWith(archivePath,".tar.gz") || endsWith(archivePath,".tgz") || endsWith(archivePath,".gz") ) utils::untar(archivePath, exdir=tmpInstallDirectory, tar="internal")
  else stop(paste0("Unrecognized file type for ", archivePath))
  home <- list.files(tmpInstallDirectory, full.names=TRUE)
  if ( length(home) != 1 ) stop(paste0("Expected only one directory in ",tmpInstallDirectory))
  finalPath <- file.path(parentDirectory, directoryName)
  if ( file.exists(finalPath) ) unlink(finalPath, TRUE, TRUE)
  homeOnMac <- file.path(home,"Contents","Home")
  if ( file.exists(homeOnMac) ) home <- homeOnMac
  status <- file.rename(home, finalPath)
  if ( ! status ) stop(paste0("Problem renaming ", home, " to ", finalPath))
  unlink(tmpInstallDirectory, TRUE, TRUE)
  filesInBin <- list.files(file.path(finalPath,"bin"),full.names=TRUE)
  Sys.chmod(filesInBin, "0755")
  finalPath
}

#' @importFrom utils download.file
#' @importFrom tools md5sum
#' 
installSoftware <- function(installPath, software, version, os, arch, verbose=FALSE, downloadFailureCount=0, extractFailureCount=0) {
  sel <- urls$software == software
  if ( missing(version) ) {
    version <- if ( software == "java" ) {
      if ( Sys.getenv("RSCALA_JAVA_VERSION","") != "" )  Sys.getenv("RSCALA_JAVA_VERSION","") else "17"
    } else if ( software == "scala" ) {
      if ( Sys.getenv("RSCALA_SCALA_VERSION","") != "" ) Sys.getenv("RSCALA_SCALA_VERSION","") else "2.13"
    } else if ( software == "sbt" ) {
      if ( Sys.getenv("RSCALA_SBT_VERSION","") != "" ) Sys.getenv("RSCALA_SBT_VERSION","") else "1.8"
    } else NULL
  }
  sel <- sel & (urls$version == version)
  if ( missing(os) ) {
    os <-  if ( software == "java" ) osType() else "any"
  }
  sel <- sel & (urls$os == os)
  if ( missing(arch) ) {
    arch <- if ( software == "java" ) {
      if ( Sys.getenv("RSCALA_JAVA_ARCH","") != "" ) Sys.getenv("RSCALA_JAVA_ARCH","") else R.Version()$arch
    } else "any"
  }
  sel <- if ( arch == "any" ) sel else {
    sel & sapply(urls$arch, function(re) grepl(re,arch))
  }
  urls2 <- urls[sel, ]
  urls3 <- urls2[order(as.numeric(urls2$priority),decreasing=TRUE), ]
  if ( verbose ) {
    len <- nrow(urls3)
    if ( len == 1 ) cat(paste0("There is 1 candidate.\n\n"))
    else cat(paste0("There are ",len," candidates.\n\n"))
  }
  if ( missing(downloadFailureCount) && ( Sys.getenv("RSCALA_DOWNLOAD_FAILURE_COUNT","") != "" ) ) downloadFailureCount <- as.integer(Sys.getenv("RSCALA_DOWNLOAD_FAILURE_COUNT",""))
  if ( missing(extractFailureCount)  && ( Sys.getenv("RSCALA_EXTRACT_FAILURE_COUNT", "") != "" ) ) extractFailureCount  <- as.integer(Sys.getenv("RSCALA_EXTRACT_FAILURE_COUNT", ""))
  dfc <- efc <- 0
  for ( candidate in seq_len(nrow(urls3)) ) {
    archivePath <- file.path(tempdir(), basename(urls3$url[candidate]))
    result <- try(download.file(urls3$url[candidate], archivePath, mode="wb"), silent=TRUE)
    if ( inherits(result,"try-error") || ( result != 0 ) || ( dfc < downloadFailureCount ) ) {
      dfc <- dfc + 1
      next
    }
    if ( tools::md5sum(archivePath) != urls3$md5sum[candidate] ) {
      stop("Security error: md5sum do not match.")
    }
    finalPath <- try(extractArchive(archivePath, installPath, software), silent=TRUE)
    unlink(archivePath,FALSE,TRUE)
    if ( inherits(finalPath,"try-error") || ( efc < extractFailureCount ) ) {
      efc <- efc + 1
      next
    }
    break
  }
}

javaSpecifics <- function(javaCmd,verbose) {
  if ( verbose ) cat("  ... querying Java specifics.\n")
  response <- suppressWarnings(system2(javaCmd,"-version",stdout=TRUE,stderr=TRUE))
  # Get version information
  versionRegexp <- '(java|openjdk) version "([^"]*)".*'
  line <- response[grepl(versionRegexp,response)]
  if ( length(line) != 1 ) return(paste0("cannot determine Java version.  Output is:\n",paste(response,collapse="\n")))
  versionString <- gsub(versionRegexp,"\\2",line)
  versionParts <- strsplit(versionString,"(\\.|-)")[[1]]
  versionNumberString <- if ( versionParts[1] == '1' ) versionParts[2] else versionParts[1]
  versionNumber <- tryCatch(
    as.numeric(versionNumberString),
    warning=function(e) 0
  )
  if ( versionNumber < 8 ) return(paste0("unsupported Java version: ",versionString))
  # Determine if 32 or 64 bit
  bit <- if ( any(grepl('.*64-?[bB]it.*$',response)) ||
              any(grepl('*amd64.*$',response)) ||
              any(grepl('.*GraalVM.*',response)) ) 64 else 32
  result <- list(javaCmd=javaCmd, javaMajorVersion=versionNumber, javaArchitecture=bit)
  if ( verbose ) print(result)
  result
}

setJavaEnv <- function(javaConf) {
  oldJAVACMD <- Sys.getenv("JAVACMD",unset="--unset--")
  oldJAVAHOME <- Sys.getenv("JAVA_HOME",unset="--unset--")
  if ( oldJAVACMD  == "--unset--" ) oldJAVACMD  <- NULL
  if ( oldJAVAHOME == "--unset--" ) oldJAVAHOME <- NULL
  if ( is.null(javaConf$javaCmd)  ) Sys.unsetenv("JAVACMD")   else Sys.setenv(JAVACMD= javaConf$javaCmd)
  if ( is.null(javaConf$javaHome) ) Sys.unsetenv("JAVA_HOME") else Sys.setenv(JAVA_HOME=javaConf$javaHome)
  list(javaCmd=oldJAVACMD,javaHome=oldJAVAHOME)
}

scalaMajorVersion <- function(scalaVersion) {
  if ( grepl(".*-.*",scalaVersion) ) scalaVersion
  else gsub("(^[23]\\.[0-9]+)\\..*","\\1",scalaVersion)
}

scalaSpecifics <- function(scalaCmd,javaConf,verbose) {
  if ( verbose ) cat("  ... querying Scala specifics.\n")
  oldJavaEnv <- setJavaEnv(javaConf)
  info <- tryCatch({
    system2(scalaCmd,c("-nobootcp","-nc","-e",shQuote('import util.Properties._; println(Seq(versionNumberString,scalaHome,javaHome).mkString(lineSeparator))')),stdout=TRUE,stderr=FALSE)
  }, warning=function(e) "", error=function(e) "")
  setJavaEnv(oldJavaEnv)
  if ( is.null(info[1]) || is.na(info[1]) ) {
    fullVersion <- "?"
    majorVersion <- "?"
  } else {
    fullVersion <- info[1]
    majorVersion <- scalaMajorVersion(fullVersion)
  }
  supportedVersions <- names(scalaVersionJARs())
  result <- if ( ( length(supportedVersions) > 0 ) && ! ( majorVersion %in% supportedVersions ) ) paste0("unsupported Scala version: ",majorVersion)
  else {
    if ( ( majorVersion == "2.11" ) && ( javaConf$javaMajorVersion > 8 ) ) {
      sprintf("Scala %s is not supported on Java %s.",majorVersion,javaConf$javaMajorVersion)
    } else {
      list(scalaHome=info[2], scalaCmd=scalaCmd, scalaMajorVersion=majorVersion, scalaFullVersion=fullVersion, javaHome=info[3])
    }
  }
  if ( verbose ) print(result)
  result
}

verifyDownloads <- function() {
  scalaConfig(download=c("java","scala","sbt"))
  for ( version in c("17","11","8") ) {
    for ( efc in 0:1 ) {
      Sys.setenv(RSCALA_EXTRACT_FAILURE_COUNT=efc)
      Sys.setenv(RSCALA_JAVA_VERSION=version)
      Sys.setenv(RSCALA_JAVA_ARCH="x86_64")
      cat(paste0("----------\nefc=",efc,", software='java', version=",version,"\n"))
      scalaConfig(download="java")
      s <- scala()
      cat(s * '"OKAY"',"\n\n")
      close(s)
    }
  }
  for ( version in c("2.11","2.12","2.13") ) {
    for ( efc in 0:1 ) {
      Sys.setenv(RSCALA_EXTRACT_FAILURE_COUNT=efc)
      Sys.setenv(RSCALA_SCALA_VERSION=version)
      cat(paste0("----------\nefc=",efc,", software='scala', version=",version,"\n"))
      scalaConfig(download="scala")
      s <- scala()
      cat(s * '"OKAY"',"\n\n")
      close(s)
    }
  }
  for ( version in c("1.8") ) {
    for ( efc in 0:1 ) {
      Sys.setenv(RSCALA_EXTRACT_FAILURE_COUNT=efc)
      Sys.setenv(RSCALA_SBT_VERSION=version)
      cat(paste0("----------\nefc=",efc,", software='sbt', version=",version,"\n"))
      scalaConfig(download="sbt")
      scalaSBT("sbtVersion")
      cat("\n")
    }
  }
  Sys.unsetenv(c("RSCALA_EXTRACT_FAILURE_COUNT","RSCALA_JAVA_VERSION","RSCALA_SCALA_VERSION","RSCALA_SBT_VERSION","RSCALA_JAVA_ARCH"))
}
