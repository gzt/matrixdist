#   matnormlda.R
#   MixMatrix: Classification with Matrix Variate Normal and t distributions
#   Copyright (C) 2018-9  GZ Thompson <gzthompson@gmail.com>
#
#   These functions are based on extensive modifications and reworkings
#   of the source for MASS::lda() and MASS::qda(),
#   copyright (C) 1994-2013 W. N. Venables and B. D. Ripley
#   released under GPL 2 or greater. This software is released under GPL-3.
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#     You should have received a copy of the GNU General Public License
#   along with this program; if not, a copy is available at
#   https://www.R-project.org/Licenses/




#' LDA for matrix variate distributions
#'
#' Performs linear discriminant analysis on matrix variate data.
#' This works slightly differently from the LDA function in MASS:
#' it does not sphere the data or otherwise normalize it. It presumes
#' equal variance matrices and probabilities are given as if
#' the data are from a matrix variate normal distribution.
#' The estimated variance matrices are weighted by the prior. However,
#' if there are not enough members of a class to estimate a variance,
#' this may be a problem.
#' The function does not take the formula interface. If `method = 't'`
#' is selected, this performs discrimination using the matrix variate t
#' distribution, presuming equal covariances between classes.
#'
#'
#' @param x 3-D array of matrix data indexed by the third dimension
#' @param grouping vector
#' @param prior a vector of prior probabilities of the same length
#'    as the number of classes
#' @param tol by default, `1e-4`. Tolerance parameter checks
#'    for 0 variance.
#' @param method whether to use the normal distribution (`normal`) or the
#'    t distribution (`t`). By default, normal.
#' @param nu If using the t-distribution, the degrees of freedom parameter. By
#'    default, 10.
#' @param ... Arguments passed to or from other methods, such
#'    as additional parameters to pass to `MLmatrixnorm` (e.g.,
#'    `row.mean`)
#' @param subset An index vector specifying the cases to be used in the
#'          training sample.  (NOTE: If given, this argument must be
#'          named.)
#'
#' @return Returns a list of class `matrixlda` containing
#'    the following components:
#'    \describe{
#'       \item{`prior`}{the prior probabilities used.}
#'       \item{`counts`}{the counts of group membership}
#'       \item{`means`}{the group means.}
#'       \item{`scaling`}{the scalar variance parameter}
#'       \item{`U`}{the between-row covariance matrix}
#'       \item{`V`}{the between-column covariance matrix}
#'       \item{`lev`}{levels of the grouping factor}
#'       \item{`N`}{The number of observations used.}
#'       \item{`method`}{The method used.}
#'       \item{`nu`}{The degrees of freedom parameter if the t distribution
#'            was used.}
#'       \item{`call`}{The (matched) function call.}
#'    }
#'
#' @seealso  [predict.matrixlda()], [MASS::lda()],
#'     [MLmatrixnorm()] and [MLmatrixt()]
#'     [matrixqda()], and [matrixmixture()]
#'
#' @references
#'     G Z Thompson, R Maitra, W Q Meeker, A Bastawros (2019),
#'     "Classification with the matrix-variate-t distribution", arXiv
#'     e-prints arXiv:1907.09565 <https://arxiv.org/abs/1907.09565>
#'
#'     Ming Li, Baozong Yuan, "2D-LDA: A statistical linear discriminant
#'       analysis for image matrix", Pattern Recognition Letters, Volume 26,
#'       Issue 5, 2005, Pages 527-532, ISSN 0167-8655.
#'
#'   Aaron Molstad & Adam J. Rothman (2019), "A Penalized Likelihood
#'        Method for Classification With Matrix-Valued Predictors", Journal of
#'        Computational and Graphical Statistics, 28:1, 11-22,
#'        \doi{10.1080/10618600.2018.1476249}  \CRANpkg{MatrixLDA}
#'
#'   Venables, W. N. & Ripley, B. D. (2002) Modern Applied Statistics with
#'   S. Fourth Edition. Springer, New York. ISBN 0-387-95457-0 \CRANpkg{MASS}
#'
#' @export
#'
#' @examples
#' set.seed(20180221)
#' # construct two populations of 3x4 random matrices with different means
#' A <- rmatrixnorm(30, mean = matrix(0, nrow = 3, ncol = 4))
#' B <- rmatrixnorm(30, mean = matrix(1, nrow = 3, ncol = 4))
#' C <- array(c(A, B), dim = c(3, 4, 60)) # combine together
#' groups <- c(rep(1, 30), rep(2, 30)) # define groups
#' prior <- c(.5, .5) # set prior
#' D <- matrixlda(C, groups, prior) # fit model
#' logLik(D)
#' print(D)
matrixlda <- function(x, grouping, prior, tol = 1.0e-4, method = "normal",
                      nu = 10, ..., subset) {
  if (is.null(dim(x))) {
    stop("'x' is not an array")
  }
  if (any(!is.finite(x))) {
    stop("infinite, NA or NaN values in 'x'")
  }
  if (nu == 0 || is.infinite(nu)) method <- "normal"

  if (method == "normal") nu <- NULL
  if (!missing(subset)) {
    x <- x[, , subset, drop = FALSE]
    grouping <- grouping[subset]
  }

  dims <- dim(x)
  # x is a p x q x n array
  n <- dims[3]
  p <- dims[1]
  q <- dims[2]

  if (n != length(grouping)) {
    stop("nrow(x) and length(grouping) are different")
  }
  g <- as.factor(grouping)
  lev <- lev1 <- levels(g)
  counts <- as.vector(table(g))
  if (!missing(prior)) {
    if (any(prior < 0) || round(sum(prior), 5) != 1) {
      stop("invalid 'prior'")
    }
    if (length(prior) != nlevels(g)) {
      stop("'prior' is of incorrect length")
    }
    prior <- prior[counts > 0L]
  }
  if (any(counts == 0L)) {
    empty <- lev[counts == 0L]
    warning(sprintf(
      ngettext(
        length(empty),
        "group %s is empty",
        "groups %s are empty"
      ),
      paste(empty, collapse = " ")
    ), domain = NA)
    lev1 <- lev[counts > 0L]
    g <- factor(g, levels = lev1)
    counts <- as.vector(table(g))
  }
  proportions <- counts / n
  ng <- length(proportions)
  names(prior) <- names(counts) <- lev1

  group_means <- array(0, dim = c(p, q, ng))
  for (i in seq(ng)) {
    group_means[, , i] <- .means_function(x,
      ss = NULL, ssx = NULL,
      weights = 1.0 * (g == levels(g)[i]), ...
    )
  }
  swept_group <- array(0, dims)
  for (i in seq(n)) {
    swept_group[, , i] <- x[, , i] - group_means[, , as.numeric(g[i])]
  }
  f1 <- sqrt((apply(swept_group, c(1, 2), stats::var)))
  if (any(f1 < tol)) {
    # this should be caught before this in the MLmatrixnorm stage
    const <- format((1L:(p * q)[f1 < tol]))
    stop(sprintf(
      ngettext(
        length(const),
        "variable %s appears to be constant within groups",
        "variables %s appear to be constant within groups"
      ),
      paste(const, collapse = " ")
    ),
    domain = NA
    )
  }


  if (method == "t") {
    # for method t with df specified
    u_result <- diag(p)
    v_result <- diag(q)
    varresult <- 1
    error <- 1e6
    itercount <- 0
    while (error > 1e-7 && itercount < 1e4) {
      # this loop is somewhat inelegant
      new_uresult <- matrix(0, p, p)
      new_vresult <- matrix(0, q, q)
      newvarresult <- 0
      for (i in seq(ng)) {
        varfit <- MLmatrixt(x[, , g == levels(g)[i], drop = FALSE],
          df = nu,
          U = u_result, V = v_result, ...
        )
        group_means[, , i] <- varfit$mean
        new_uresult <- new_uresult + prior[i] * varfit$U
        new_vresult <- new_vresult + prior[i] * varfit$V
        newvarresult <- newvarresult + prior[i] * varfit$var
        if (varfit$convergence == FALSE) {
          warning("ML fit failed for group ", i)
        }
      }

      error <- sum((new_uresult - u_result)^2) +
        sum((new_vresult - v_result)^2) + (varresult - newvarresult)^2
      u_result <- new_uresult
      v_result <- new_vresult
      varresult <- newvarresult
      itercount <- itercount + 1
    }
  } else {
    u_result <- matrix(0, p, p)
    v_result <- matrix(0, q, q)
    varresult <- 0
    # for (i in seq(ng)) {
    varfit <- MLmatrixnorm(swept_group, ...)
    u_result <- varfit$U
    v_result <- varfit$V
    varresult <- varfit$var
    # }
  }
  cl <- match.call()
  cl[[1L]] <- as.name("matrixlda")
  structure(
    list(
      prior = prior,
      counts = counts,
      means = group_means,
      scaling = varresult,
      U = u_result,
      V = v_result,
      lev = lev,
      N = n,
      method = method,
      nu = nu,
      call = cl
    ),
    class = "matrixlda"
  )
}


#' Classify Matrix Variate Observations by Linear Discrimination
#'
#' Classify matrix variate observations in conjunction with `matrixlda`.
#'
#' This function is a method for the generic function `predict()` for
#' class "`matrixlda`". It can be invoked by calling `predict(x)` for
#' an object `x` of the appropriate class.
#'
#'
#' @param object object of class `matrixlda`
#' @param newdata array or list of new observations to be classified.
#'     If newdata is missing, an attempt will be made to retrieve the
#'     data used to fit the `matrixlda` object.
#' @param prior The prior probabilities of the classes, by default the
#'     proportions in the training set or what was set in the call to
#'     `matrixlda`.
#' @param ... arguments based from or to other methods
#' @seealso [matrixlda()], [matrixqda()],
#'    and [matrixmixture()]

#' @return
#' Returns a list containing
#'    the following components:
#'    \describe{
#'       \item{`class`}{The MAP classification (a factor)}
#'       \item{`posterior`}{posterior probabilities for the classes}
#'    }
#'
#' @export
#'
#' @examples
#' set.seed(20180221)
#' # construct two populations of 3x4 random matrices with different means
#' A <- rmatrixnorm(30, mean = matrix(0, nrow = 3, ncol = 4))
#' B <- rmatrixnorm(30, mean = matrix(1, nrow = 3, ncol = 4))
#' C <- array(c(A, B), dim = c(3, 4, 60)) # combine together
#' groups <- c(rep(1, 30), rep(2, 30)) # define groups
#' prior <- c(.5, .5) # set prior
#' D <- matrixlda(C, groups, prior)
#' predict(D)$posterior[1:10, ]
#'
#' ## S3 method for class 'matrixlda'
predict.matrixlda <- function(object, newdata, prior = object$prior, ...) {
  if (!inherits(object, "matrixlda")) {
    stop("object not of class \"matrixlda\"")
  }

  if (missing(newdata)) {
    if (!is.null(sub <- object$call$subset)) {
      newdata <-
        eval.parent(parse(text = paste(
          deparse(object$call$x,
            backtick = TRUE
          ),
          "[,,",
          deparse(sub, backtick = TRUE),
          ",drop = FALSE]"
        )))
    } else {
      newdata <- eval.parent(object$call$x)
    }
    if (!is.null(nas <- object$call$na.action)) {
      newdata <- eval(call(nas, newdata))
    }
  }


  if (any(!is.finite(newdata))) {
    stop("infinite, NA or NaN values in 'newdata'")
  }

  x <- (newdata)
  if (is.null(dim(x))) {
    stop("'newdata' is not an array")
  }

  if (length(dim(x)) == 2) x <- array(x, dim = c(dim(x), 1))


  if (ncol(x[, , 1, drop = FALSE]) != ncol(object$means[, , 1, drop = FALSE])) {
    stop("wrong column dimension of matrices")
  }
  if (nrow(x[, , 1, drop = FALSE]) != nrow(object$means[, , 1, drop = FALSE])) {
    stop("wrong row dimension of matrices")
  }
  ng <- length(object$prior)
  if (!missing(prior)) {
    if (length(prior) != ng) stop("invalid prior length")
    if (any(prior < 0) || round(sum(prior), 5) != 1) {
      stop("invalid 'prior'")
    }
  }


  dims <- dim(x)
  # x is a p x q x n array
  n <- dims[3]
  if (object$method == "t") df <- object$nu
  dist <- matrix(0, nrow = n, ncol = ng)
  posterior <- matrix(0, nrow = n, ncol = ng)
  ## solveV = matrix(solve(object$V * object$scaling),q,q)
  ## solveU = matrix(solve(object$U),p,p)
  ## VMUM = vector("list", ng)
  ## VMU = vector("list", ng)
  ## for (j in seq(ng)) {
  ##   VMU[[j]] = solveV %*% crossprod(matrix(object$means[, , j],p,q), solveU )
  ##   VMUM[[j]] =  VMU[[j]] %*% object$means[, , j]
  ## }

  ## for (i in seq(n)) {
  ##   Xi = matrix(x[, , i],p,q)
  ##   # if (object$method == "t") UXVX = solveV %*% crossprod(Xi,  solveU) %*% (Xi)
  ##   for (j in seq(ng)) {
  ##     if (object$method == "t") {
  ##       dist[i, j] = -.5 * (df + p + q -1) * log(det(diag(q) + solveV %*% t(Xi - object$means[,,j]) %*% solveU %*% ((Xi - object$means[,,j])))) +
  ##                                             log(prior[j])
  ##     } else dist[i, j] = matrixtrace(VMU[[j]] %*% Xi) +  matrixtrace(-.5*VMUM[[j]]) + log(prior[j])
  ##   }
  ## }

  for (j in seq(ng)) {
    if (object$method == "t") {
      dist[, j] <- dmat_t_calc(
        x, df, object$means[, , j], object$U,
        object$V * object$scaling
      ) + log(prior[j])
    } else {
      dist[, j] <- dmatnorm_calc(
        x, object$means[, , j], object$U,
        object$V * object$scaling
      ) + log(prior[j])
    }
  }

  dist <- ((dist - apply(dist, 1L, max, na.rm = TRUE)))
  posterior <- exp(dist)
  totalpost <- rowSums(posterior)
  posterior <- posterior / totalpost
  nm <- names(object$prior)
  cl <- factor(nm[max.col(posterior)], levels = object$lev)
  list(class = cl, posterior = posterior)
}


#' Quadratic Discriminant Analysis for Matrix Variate Observations
#'
#' See `matrixlda`: quadratic discriminant analysis for matrix
#' variate observations.
#'
#' This uses `MLmatrixnorm` or `MLmatrixt` to find the means and
#' variances for the case when different groups have different variances.
#'
#' @inheritParams matrixlda
#'
#' @return Returns a list of class `matrixqda` containing
#'    the following components:
#'    \describe{
#'       \item{`prior`}{the prior probabilities used.}
#'       \item{`counts`}{the counts of group membership}
#'       \item{`means`}{the group means.}
#'       \item{`U`}{the between-row covariance matrices}
#'       \item{`V`}{the between-column covariance matrices}
#'       \item{`lev`}{levels of the grouping factor}
#'       \item{`N`}{The number of observations used.}
#'       \item{`method`}{The method used.}
#'       \item{`nu`}{The degrees of freedom parameter
#'      if the t-distribution was used.}
#'       \item{`call`}{The (matched) function call.}
#'    }
#'
#' @seealso [predict.matrixqda()], [MASS::qda()],
#'     [MLmatrixnorm()], [MLmatrixt()],
#'     [matrixlda()], and [matrixmixture()]

#'
#' @references
#'     G Z Thompson, R Maitra, W Q Meeker, A Bastawros (2019),
#'     "Classification with the matrix-variate-t distribution", arXiv
#'     e-prints arXiv:1907.09565 <https://arxiv.org/abs/1907.09565>
#'
#'   Venables, W. N. & Ripley, B. D. (2002) Modern Applied Statistics with
#'   S. Fourth Edition. Springer, New York. ISBN 0-387-95457-0
#'
#'     Pierre Dutilleul.  The MLE algorithm for the matrix normal distribution.
#'     Journal of Statistical Computation and Simulation, (64):105–123, 1999.
#'
#' @export
#'
#' @examples
#' set.seed(20180221)
#' # construct two populations of 3x4 random matrices with different means
#' A <- rmatrixnorm(30, mean = matrix(0, nrow = 3, ncol = 4))
#' B <- rmatrixnorm(30, mean = matrix(1, nrow = 3, ncol = 4))
#' C <- array(c(A, B), dim = c(3, 4, 60)) # combine together
#' groups <- c(rep(1, 30), rep(2, 30)) # define groups
#' prior <- c(.5, .5) # set prior
#' D <- matrixqda(C, groups, prior)
#' logLik(D)
#' print(D)
matrixqda <- function(x, grouping, prior, tol = 1.0e-4,
                      method = "normal", nu = 10, ..., subset) {
  if (is.null(dim(x))) {
    stop("'x' is not an array")
  }
  if (any(!is.finite(x))) {
    stop("infinite, NA or NaN values in 'x'")
  }
  if (nu == 0 || is.infinite(nu)) method <- "normal"
  if (method == "normal") df <- NULL
  if (!missing(subset)) {
    x <- x[, , subset, drop = FALSE]
    grouping <- grouping[subset]
  }

  dims <- dim(x)
  # x is a p x q x n array
  n <- dims[3]
  p <- dims[1]
  q <- dims[2]
  if (n != length(grouping)) {
    stop("nrow(x) and length(grouping) are different")
  }
  g <- as.factor(grouping)
  lev <- lev1 <- levels(g)
  counts <- as.vector(table(g))
  if (!missing(prior)) {
    if (any(prior < 0) ||
      round(sum(prior), 5) != 1) {
      stop("invalid 'prior'")
    }
    if (length(prior) != nlevels(g)) {
      stop("'prior' is of incorrect length")
    }
    prior <- prior[counts > 0L]
  }
  if (any(counts == 0L)) {
    empty <- lev[counts == 0L]
    warning(sprintf(
      ngettext(
        length(empty),
        "group %s is empty",
        "groups %s are empty"
      ),
      paste(empty, collapse = " ")
    ), domain = NA)
    lev1 <- lev[counts > 0L]
    g <- factor(g, levels = lev1)
    counts <- as.vector(table(g))
  }
  proportions <- counts / n
  ng <- length(proportions)
  names(prior) <- names(counts) <- lev1
  if (method == "t") {
    if (length(nu) != ng) {
      df <- rep_len(nu, ng)
    } # if you mismatch lengths, you will not have a good time
  }
  group_means <- array(0, dim = c(p, q, ng))
  group_u <- array(0, dim = c(p, p, ng))
  group_v <- array(0, dim = c(q, q, ng))
  for (i in seq(ng)) {
    # hiding this there: , ...
    if (method == "t") {
      mlfit <- MLmatrixt(x[, , g == levels(g)[i], drop = FALSE],
        df = df[i], ...
      )
      df[i] <- mlfit$nu
    } else {
      mlfit <- MLmatrixnorm(x[, , g == levels(g)[i], drop = FALSE], ...)
    }
    if (mlfit$convergence == FALSE) {
      warning("ML fit failed for group ", i)
    }

    group_means[, , i] <- mlfit$mean
    group_u[, , i] <- mlfit$U
    group_v[, , i] <- mlfit$V * mlfit$var
  }
  swept_group <- array(0, dims)
  for (i in seq(n)) {
    swept_group[, , i] <- x[, , i] - group_means[, , as.numeric(g[i])]
  }
  f1 <- sqrt((apply(swept_group, c(1, 2), stats::var)))
  if (any(f1 < tol)) {
    # this should be caught before this in the MLmatrixnorm stage
    const <- format((1L:(p * q)[f1 < tol]))
    stop(sprintf(
      ngettext(
        length(const),
        "variable %s appears to be constant within groups",
        "variables %s appear to be constant within groups"
      ),
      paste(const, collapse = " ")
    ),
    domain = NA
    )
  }



  cl <- match.call()
  cl[[1L]] <- as.name("matrixqda")
  structure(
    list(
      prior = prior,
      counts = counts,
      means = group_means,
      U = group_u,
      V = group_v,
      lev = lev,
      N = n,
      method = method,
      nu = df,
      call = cl
    ),
    class = "matrixqda"
  )
}

#' Variance parser for DF
#'
#' Parses out how many DF are involved with the variance choices.
#' @keywords internal
#' @noRd
#' @param var variance flag (col.variance or row.variance)
#' @param dim p or q depending on above
.var_parse_df <- function(var, dim) {
    vpars  <-  (dim + 1) * dim / 2
    if (grepl("^ar", x = var, ignore.case = TRUE)) vpars <- 2

    if (grepl("^cs", x = var, ignore.case = TRUE)) vpars <- 2

    if (grepl("^i", x = var, ignore.case = TRUE)) vpars <- 1

    if (grepl("^cor", x = var, ignore.case = TRUE)) {
      vpars <- (dim - 1) * dim / 2 + 1
    }
    vpars
}


#' @export
logLik.matrixlda <- function(object, ...) {
  if (!is.null(sub <- object$call$subset)) {
    olddata <-
      eval.parent(parse(text = paste(
        deparse(object$call$x,
          backtick = TRUE
        ),
        "[,,",
        deparse(sub, backtick = TRUE),
        ",drop = FALSE]"
      )))
    groups <-
      eval.parent(parse(text = paste(
        deparse(object$call$grouping,
          backtick = TRUE
        ),
        "[",
        deparse(sub, backtick = TRUE),
        "]"
      )))
  } else {
    olddata <- eval.parent(object$call$x)
    groups <- eval.parent(object$call$grouping)
  }

  groups <- factor(groups)
  dims <- dim(olddata)
  n <- dims[3]
  p <- dims[1]
  q <- dims[2]
  numgroups <- length(levels(groups))
  grouplist <- levels(groups)
  meanpars <- p * q
  upars <- (p + 1) * p / 2
  vpars <- (q + 1) * q / 2 # there's one par that will get subbed off variance
  nupar <- 0 # if nu not fixed, becomes 1

  if (!is.null(object$call$row.mean) && (object$call$row.mean)) {
    meanpars <- meanpars / q
  }

  if (!is.null(object$call$col.mean) && (object$call$col.mean)) {
    meanpars <- meanpars / p
  }

 
  if (!is.null(object$call$col.variance)) {
      vpars  <- .var_parse_df(object$call$col.variance, q)
  }
  if (!is.null(object$call$row.variance)) {
      upars  <- .var_parse_df(object$call$row.variance, p)
  }

  if (!is.null(object$call$fixed) && !(object$call$fixed)) nupar <- 1

  df <- vpars + upars + nupar + numgroups * meanpars - 1
  log_lik <- 0
  if (is.null(object$nu)) {
    nu <- 0
  } else {
    nu <- object$nu
  }
  if (object$method == "normal") {
    for (i in 1:numgroups) {
      log_lik <- log_lik + sum(dmatnorm_calc(
        x = olddata[, , groups == grouplist[i], drop = FALSE],
        mean = object$means[, , i],
        U = object$U * object$scaling, V = object$V
      ))
    }
  } else {
    for (i in 1:numgroups) {
      log_lik <- log_lik + sum(dmat_t_calc(
        x = olddata[, , groups == grouplist[i], drop = FALSE],
        df = nu, mean = object$means[, , i],
        U = object$U * object$scaling, V = object$V
      ))
    }
  }

  class(log_lik) <- "logLik"
  attr(log_lik, "df") <- df
  attr(log_lik, "nobs") <- n
  log_lik
}

#' @export
logLik.matrixqda <- function(object, ...) {
  if (!is.null(sub <- object$call$subset)) {
    data <-
      eval.parent(parse(text = paste(
        deparse(object$call$x,
          backtick = TRUE
        ),
        "[,,",
        deparse(sub, backtick = TRUE),
        ",drop = FALSE]"
      )))
    grouping <-
      eval.parent(parse(text = paste(
        deparse(object$call$grouping,
          backtick = TRUE
        ),
        "[",
        deparse(sub, backtick = TRUE),
        "]"
      )))
  }
  else {
    data <- eval.parent(object$call$x)
    grouping <- eval.parent(object$call$grouping)
  }
  if (!is.null(nas <- object$call$na.action)) {
    data <- eval(call(nas, data))
  }

  grouping <- factor(grouping)
  dims <- dim(data)
  n <- dims[3]
  p <- dims[1]
  q <- dims[2]
  numgroups <- length(levels(grouping))
  grouplist <- levels(grouping)
  meanpars <- p * q
  upars <- (p + 1) * p / 2
  vpars <- (q + 1) * q / 2 #  there's one par that will get subbed off variance
  nupar <- 0 # if nu not fixed, becomes 1

  if (!is.null(object$call$row.mean) && (object$call$row.mean)) {
    meanpars <- meanpars / q
  }

  if (!is.null(object$call$col.mean) && (object$call$col.mean)) {
    meanpars <- meanpars / p
  }

  if (!is.null(object$call$col.variance)) {
      vpars  <- .var_parse_df(object$call$col.variance, q)
  }
  if (!is.null(object$call$row.variance)) {
      upars  <- .var_parse_df(object$call$row.variance, p)
  }

  if (!is.null(object$call$fixed) && !(object$call$fixed)) nupar <- 1

  df <- numgroups * (vpars + upars + nupar + meanpars - 1)
  log_lik <- 0
  if (is.null(object$nu)) {
    nu <- 0
  } else {
    nu <- object$nu
  }

  for (i in 1:numgroups) {
    if (object$method == "t") {
      log_lik <- log_lik + sum(dmat_t_calc(
        x = data[, , grouping == grouplist[i], drop = FALSE],
        df = nu[i], mean = object$means[, , i],
        U = object$U[, , i], V = object$V[, , i]
      ))
    } else {
      log_lik <- log_lik + sum(dmatnorm_calc(
        x = data[, , grouping == grouplist[i], drop = FALSE],
        mean = object$means[, , i],
        U = object$U[, , i], V = object$V[, , i]
      ))
    }
  }
  class(log_lik) <- "logLik"
  attr(log_lik, "df") <- df
  attr(log_lik, "nobs") <- n
  log_lik
}

#' @importFrom stats nobs
#' @export
nobs.matrixlda <- function(object, ...) {
  object$N
}

#' @importFrom stats nobs
#' @export
nobs.matrixqda <- function(object, ...) {
  object$N
}


#' Classify Matrix Variate Observations by Quadratic Discrimination
#'
#' Classify matrix variate observations in conjunction with `matrixqda`.
#'
#' This function is a method for the generic function `predict()` for
#' class "`matrixqda`". It can be invoked by calling `predict(x)` for
#' an object `x` of the appropriate class.
#'
#'
#'
#' @param object object of class `matrixqda`
#' @param newdata array or list of new observations to be classified.
#'     If newdata is missing, an attempt will be made to retrieve the
#'     data used to fit the `matrixqda` object.
#' @param prior The prior probabilities of the classes, by default the
#'     proportions in the training set or what was set in the call to
#'     `matrixqda`.
#' @param ... arguments based from or to other methods
#'
#' @return
#' Returns a list containing
#'    the following components:
#'    \describe{
#'       \item{`class`}{The MAP classification (a factor)}
#'       \item{`posterior`}{posterior probabilities for the classes}
#'    }
#'
#' @seealso [matrixlda()], [matrixqda()],
#' and [matrixmixture()]
#' @export
#'

#' @examples
#'
#' set.seed(20180221)
#' # construct two populations of 3x4 random matrices with different means
#' A <- rmatrixnorm(30, mean = matrix(0, nrow = 3, ncol = 4))
#' B <- rmatrixnorm(30, mean = matrix(1, nrow = 3, ncol = 4))
#' C <- array(c(A, B), dim = c(3, 4, 60)) # combine together
#' groups <- c(rep(1, 30), rep(2, 30)) # define groups
#' prior <- c(.5, .5) # set prior
#' D <- matrixqda(C, groups, prior) # fit model
#' predict(D)$posterior[1:10, ] # predict, show results of first 10
#' ## S3 method for class "matrixqda"
predict.matrixqda <- function(object, newdata, prior = object$prior, ...) {
  if (!inherits(object, "matrixqda")) {
    stop("object not of class \"matrixqda\"")
  }

  if (missing(newdata)) {
    if (!is.null(sub <- object$call$subset)) {
      newdata <-
        eval.parent(parse(text = paste(
          deparse(object$call$x,
            backtick = TRUE
          ),
          "[,,",
          deparse(sub, backtick = TRUE),
          ",drop = FALSE]"
        )))
    } else {
      newdata <- eval.parent(object$call$x)
    }
    if (!is.null(nas <- object$call$na.action)) {
      newdata <- eval(call(nas, newdata))
    }
  }

  if (is.null(dim(newdata))) {
    stop("'newdata' is not an array")
  }
  if (any(!is.finite(newdata))) {
    stop("infinite, NA or NaN values in 'newdata'")
  }
  x <- (newdata)


  if (length(dim(x)) == 2) x <- array(x, dim = c(dim(x), 1))

  if (ncol(x[, , 1, drop = FALSE]) != ncol(object$means[, , 1, drop = FALSE])) {
    stop("wrong column dimension of matrices")
  }
  if (nrow(x[, , 1, drop = FALSE]) != nrow(object$means[, , 1, drop = FALSE])) {
    stop("wrong row dimension of matrices")
  }
  ng <- length(object$prior)
  if (!missing(prior)) {
    if (length(prior) != ng) stop("invalid prior length")
    if (any(prior < 0) || round(sum(prior), 5) != 1) {
      stop("invalid 'prior'")
    }
  }

  dims <- dim(x)
  # x is a p x q x n array
  n <- dims[3]
  df <- object$nu
  ##### Here is where the work needs to be done.
  dist <- matrix(0, nrow = n, ncol = ng)
  posterior <- matrix(0, nrow = n, ncol = ng)

  for (j in seq(ng)) {
    if (object$method == "t") {
      dist[, j] <- dmat_t_calc(
        x, df[j], object$means[, , j], object$U[, , j],
        object$V[, , j]
      ) + log(prior[j])
    } else {
      dist[, j] <- dmatnorm_calc(
        x, object$means[, , j], object$U[, , j],
        object$V[, , j]
      ) + log(prior[j])
    }
  }

  posterior <- exp((dist - apply(dist, 1L, max, na.rm = TRUE)))
  totalpost <- rowSums(posterior)
  posterior <- posterior / totalpost
  nm <- names(object$prior)
  cl <- factor(nm[max.col(posterior)], levels = object$lev)
  list(class = cl, posterior = posterior)
}

#' @export
#' @importFrom utils head
print.matrixlda <- function(x, ...) {
  x[["posterior"]] <- head(x[["posterior"]])
  print.default(x, ...)
}

#' @export
print.matrixqda <- function(x, ...) {
  x[["posterior"]] <- head(x[["posterior"]])
  print.default(x, ...)
}
