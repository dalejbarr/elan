#' Define an ELAN annotation tree from file
#' @param fname Name of xml or eaf file to read from
#' @return parsed xml tree
#' @importFrom XML xmlInternalTreeParse
#' @export
elanTree <- function(fname) {
    if (!file.exists(fname)) {
        stop("file '", fname, "' does not exist; check working directory")
    } else {}
    XML::xmlInternalTreeParse(fname)
}

#' @importFrom XML xmlGetAttr
processTimeSlot <- function(node) {
    data.frame(tsid=XML::xmlGetAttr(node, "TIME_SLOT_ID"),
               tstime=as.numeric(XML::xmlGetAttr(node, "TIME_VALUE")),
               stringsAsFactors=FALSE)
}

#' Read in the time slots
#'
#' @param doc parsed XML tree (see \code{\link{elanTree}})
#' @return data frame with timeslot IDs and values
#' @importFrom XML getNodeSet
#' @importFrom plyr ldply
#' @export
readTimeSlots <- function(doc) {
    nodelist <- XML::getNodeSet(doc, "//TIME_SLOT")
    ldply(nodelist, processTimeSlot)
}

#' @importFrom plyr ldply
#' @importFrom XML xmlAttrs
readWithMissing <- function(nodes, reqAttr, optAttr) {
    oldOpts <- options()$stringsAsFactors
    options(stringsAsFactors=FALSE)    
    optAttrNA <- rep(NA_character_, length(optAttr))
    names(optAttrNA) <- optAttr
    nord <- c(reqAttr, optAttr)
    res <- plyr::ldply(nodes, function(x) {
        # which of the optional attributes are defined?
        defAttr <- XML::xmlAttrs(x)
        exAttr <- setdiff(names(defAttr), reqAttr)
        undefAttr <- setdiff(names(optAttrNA), exAttr)
        attrlist <- c(as.list(defAttr[reqAttr]), as.list(defAttr), optAttrNA[undefAttr])
        as.data.frame(attrlist[nord])
    })
    options(stringsAsFactors=oldOpts)
    return(res)
}

#' Read annotations from the ELAN tree
#'
#' @param doc the ELAN tree
#' @param annType either \code{"ALIGNABLE"} for time-stamped annotations or \code{"REF"} for reference annotations
#' @param tierId tier to read annotations from; if \code{NULL} will read from all tiers (default)
#' @param dropNACols boolean; drop any columns in the resulting dataset where all values are NAs (default is \code{TRUE})
#' @return data frame with tier attributes and annotations in the field \code{VALUE}
#' @importFrom XML getNodeSet
#' @importFrom XML xmlGetAttr
#' @importFrom XML xmlSApply
#' @importFrom XML getChildrenStrings
#' @importFrom plyr ldply
#' @export
readAnnotations <- function(doc, annType="ALIGNABLE", tierId=NULL, dropNACols=TRUE) {
    if (!(annType %in% c("ALIGNABLE", "REF"))) {
        stop("'annType' must be either 'ALIGNABLE' or 'REF'")
    } else {}
    sstr <- paste0("./ANNOTATION/", annType, "_ANNOTATION")
    oldOpts <- options()$stringsAsFactors
    options(stringsAsFactors=FALSE)
    # focus on the part of the tree we are interested in
    if (is.null(tierId)) {
        tnodes <- XML::getNodeSet(doc, "/ANNOTATION_DOCUMENT/TIER")
    } else {
        # TODO: search for a specific tier
        stop("getting annotations for a single tier not supported yet")
    }
    if (annType=="ALIGNABLE") {
        reqAttr <- c("ANNOTATION_ID", "TIME_SLOT_REF1", "TIME_SLOT_REF2")
        optAttr <- c("SVG_REF", "EXT_REF")
    } else {
        reqAttr <- c("ANNOTATION_ID", "ANNOTATION_REF")
        optAttr <- c("PREVIOUS_ANNOTATION", "EXT_REF")
    }
    res <- plyr::ldply(tnodes, function(node) {
        thisID <- XML::xmlGetAttr(node, "TIER_ID")
        anodes <- XML::getNodeSet(node, sstr)
        dat <- readWithMissing(anodes, reqAttr, optAttr)
        if (nrow(dat)>0) {
            dat$TIER_ID <- thisID
            dat$VALUE <- XML::xmlSApply(anodes, XML::getChildrenStrings)
        } else {}
        dat
    })[,c("TIER_ID", reqAttr, "VALUE", optAttr)]
    # TODO: UNHACK!!
    if (is.list(res$VALUE)) {
        res$VALUE <- unlist(res$VALUE)
    } else {}
    if (annType=="ALIGNABLE") { # convert timeslot ids to values
        tslots <- readTimeSlots(doc)
        res1 <- res %>% mutate(tsid=TIME_SLOT_REF1) %>%
            inner_join(tslots, by="tsid") %>%
                mutate(t0.id=tsid, t0=tstime, tsid=TIME_SLOT_REF2) %>%
                    select(-tstime, -TIME_SLOT_REF1, -TIME_SLOT_REF2)
        res2 <- res1 %>% inner_join(tslots, by="tsid") %>%
            mutate(t1.id=tsid, t1=tstime) %>%
                select(-tstime, -tsid)
    } else {
        res2 <- res
    }
    if (dropNACols) { # TODO do something
        keep.cols <- sapply(res2, function(x) sum(!is.na(x))>0)
    } else {
        keep.cols <- rep(TRUE, ncol(res2))
    } # do nothing
    options(stringsAsFactors=oldOpts)
    return(res2[,keep.cols])
}


#' Read the list of tiers in the ELAN file
#' 
#' @param doc the xml parse tree for the ELAN file
#' @param inheritMissingAttrs inherit missing attributes from parent tier (default=\code{TRUE})
#' @return a data frame, where the rows are tiers and columns are attributes
#' @importFrom XML getNodeSet
#' @importFrom XML xmlAttrs
#' @importFrom plyr ldply
#' @export
readTierList <- function(doc, inheritMissingAttrs=TRUE) {
    oldOpts <- options()$stringsAsFactors
    options(stringsAsFactors=FALSE)    
    tiers <- XML::getNodeSet(doc, "/ANNOTATION_DOCUMENT/TIER")
    reqAttr <- c("TIER_ID", "LINGUISTIC_TYPE_REF")
    optAttr <- c("PARTICIPANT", "ANNOTATOR", "DEFAULT_LOCALE", "PARENT_REF")
    res <- readWithMissing(tiers, reqAttr, optAttr)
    # now inherit any missing attributes
    if (inheritMissingAttrs) {
        fixedFields <- ldply(1:nrow(res), function(rx) {
            reprow <- lapply(setdiff(optAttr, "PARENT_REF"), function(ox) {
                if (is.na(res[rx,ox])) { # search parent tree
                    val <- NA_character_
                    cur <- res[rx,"TIER_ID"]
                    while(is.na(val)) {
                        # get parent
                        parID <- res[res$TIER_ID==cur,"PARENT_REF"]
                        val <- res[parID,ox]
                        cur <- parID
                        if (is.na(cur)) break;
                    }
                    val
                } else {
                    # keep what we have
                    res[rx,ox]
                }
            })
                             names(reprow) <- setdiff(optAttr, "PARENT_REF")
            as.data.frame(reprow)
        })
        nord <- colnames(res)
        res <- cbind(res[,c(reqAttr, "PARENT_REF")], fixedFields)[,nord]
    } else {}
    options(stringsAsFactors=oldOpts)
    return(res)
}

#' Read in the annotations from a multiple files
#'
#' Read in annotations from multiple ELAN files
#' @param fileName vector of filenames
#' @return a data frame
#' @importFrom plyr ldply
#' @export
efileAnnotations <- function(fileName) {
    ldply(fileName, function(x) {
               doc <- elanTree(x)
               align_ann <- readAnnotations(doc) %>%
                   mutate(filename = x, atype = "ANN")
               align_ref <- readAnnotations(doc, "REF") %>%
                   mutate(filename = x, atype = "REF")
               bind_rows(align_ann, align_ref)
           })
}

#' List all tiers in elan file(s)
#'
#' List all annotation tiers in single or multiple ELAN files
#' @param fileName vector of filenames
#' @param inheritMissingAttr inherit missing attributes from parent tier (default=\code{TRUE})
#' @importFrom plyr ldply
#' @return a data frame
#' @seealso \code{\link{readTierList}}
#' @export
efileTierList <- function(fileName, inheritMissingAttr = TRUE) {
    ldply(fileName, function(x) {
               doc <- elanTree(x)
               tiers <- readTierList(doc, inheritMissingAttr) %>%
                   mutate(filename = x)
           })
}
