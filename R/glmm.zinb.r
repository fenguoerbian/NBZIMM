
# modify "glmmPQL" in package MASS

glmm.zinb <- function (fixed, random, data, correlation, 
                       zi_fixed = ~1, zi_random = NULL,
                       niter = 30, epsilon = 1e-05, verbose = TRUE, ...)
{ 
  if (!requireNamespace("nlme")) install.packages("nlme")
  if (!requireNamespace("MASS")) install.packages("MASS") 
  library(nlme)
  library(MASS)
  
    start.time <- Sys.time()
    if (missing(data)) stop("'data' should be specified")
    family <- NegBin()
    m <- mcall <- Call <- match.call()
    nm <- names(m)[-1L]
    keep <- is.element(nm, c("weights", "data", "subset", "na.action"))
    for (i in nm[!keep]) m[[i]] <- NULL
    allvars <- if (is.list(random))
        allvars <- c(all.vars(fixed), names(random), unlist(lapply(random,
            function(x) all.vars(formula(x)))))
    else c(all.vars(fixed), all.vars(random))
    Terms <- if (missing(data)) terms(fixed)
    else terms(fixed, data = data)
    off <- attr(Terms, "offset")
    if (length(off <- attr(Terms, "offset")))
        allvars <- c(allvars, as.character(attr(Terms, "variables"))[off + 1])
    if (!missing(correlation) && !is.null(attr(correlation, "formula")))
        allvars <- c(allvars, all.vars(attr(correlation, "formula")))
    Call$fixed <- eval(fixed)
    Call$random <- eval(random)
    m$formula <- as.formula(paste("~", paste(allvars, collapse = "+")))
    environment(m$formula) <- environment(fixed)
    m$drop.unused.levels <- TRUE
    m[[1L]] <- quote(stats::model.frame)
    mf <- eval.parent(m)
    off <- model.offset(mf)
    if (is.null(off)) off <- 0
    wts <- model.weights(mf)
    if (is.null(wts)) wts <- rep(1, nrow(mf))
    mf$wts <- wts
    fit0 <- suppressWarnings( glm(formula = fixed, family = family, data = mf) )

    w <- fit0$prior.weights
    eta <- fit0$linear.predictors
    zz <- eta + fit0$residuals - off
    wz <- fit0$weights
    fam <- family
    nm <- names(mcall)[-1L]
    keep <- is.element(nm, c("fixed", "random", "data", "subset", "na.action", "control"))
    for (i in nm[!keep]) mcall[[i]] <- NULL
    fixed[[2L]] <- quote(zz)
    mcall[["fixed"]] <- fixed
    mcall[[1L]] <- quote(nlme::lme)
    mcall$random <- random
    mcall$method <- "ML"
    if (!missing(correlation)) mcall$correlation <- correlation
    mcall$weights <- quote(nlme::varFixed(~invwt))
    mf$zz <- zz
    mf$invwt <- 1/(wz + 1e-04)
    mcall$data <- mf
    
    y <- fit0$y 
    if (all(y != 0)) stop("invalid response: no zero")
    zp <- ifelse(y!=0, 0, 0.5)
    fm <- zp ~ .
    fm[[3]] <- zi_fixed[[2]]
    zero.eta <- fit.zinb <- NA
       
    for (i in seq_len(niter)) {
      fit <- eval(mcall)
      etaold <- eta
      eta <- fitted(fit) + off
      if (i > 1 & sum((eta - etaold)^2) < epsilon * sum(eta^2)) break
      mu <- fam$linkinv(eta)
      mu.eta.val <- fam$mu.eta(eta)
      mu.eta.val <- ifelse(mu.eta.val == 0, 1e-04, mu.eta.val)  
      varmu <- fam$variance(mu)
      varmu <- ifelse(varmu == 0, 1e-04, varmu)
      mf$zz <- eta + (y - mu)/mu.eta.val - off
      wz <- w * mu.eta.val^2/varmu
      wz <- ifelse(wz == 0, 1e-04, wz)
      mf$invwt <- 1/wz
      mcall$data <- mf
      
      ww <- wts * (1 - zp)
      th <- suppressWarnings( theta.ml(y=y, mu=mu, n=sum(ww), weights=ww, limit=10, trace=FALSE) )
      if (is.null(th)) th <- fam$theta
      fam <- NegBin(theta = th)
      
      if (is.null(zi_random)){
        fit.zinb <- suppressWarnings(glm(fm, family=binomial, data=data))
        zero.eta <- fit.zinb$linear.predictors
      }
      else{
        fit.zinb <- suppressWarnings(glmmPQL(fixed=fm, random=zi_random, family=binomial, data=data, verbose = FALSE, 
                                             control = lmeControl(returnObject = TRUE)))
        zero.eta <- fitted(fit.zinb)
        if (!is.null(fit.zinb$offset)) zero.eta <- zero.eta + fit.zinb$offset
      }
      
      den <- dnbinom(y, size = th, mu = mu)
      zp <- 1/(1 + exp(-zero.eta) * den )
      zp <- ifelse(zp > 0.95, 0.95, zp)
      zp <- ifelse(y != 0, 0, zp)
      wz <- (1 - zp) * wz 
      mf$invwt <- 1/wz
      mcall$data <- mf
    }
  
    attributes(fit$logLik) <- NULL
    fit$call <- Call
    fit$iter <- i
    fit$logLik <- as.numeric(NA)
    
    fit$theta <- fam$theta
    fit$zero.indicator <- zp
    fit$zero.prob <- exp(zero.eta)/(1 + exp(zero.eta))
    fit$fit.zero <- fit.zinb 

    oldClass(fit) <- c("zinbmm", oldClass(fit))
    
    stop.time <- Sys.time()
    minutes <- round(difftime(stop.time, start.time, units = "min"), 3)
    if (verbose) {
     cat("Computational iterations:", fit$iter, "\n")
     cat("Computational time:", minutes, "minutes \n")
    }
  
    fit
}


#*********************************************************************************************

