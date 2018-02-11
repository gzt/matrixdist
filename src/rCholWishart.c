/*
  *  R : A Computer Language for Statistical Data Analysis
*  Copyright (C) 2012-2016  The R Core Team
*  Original file rWishart.c altered by GZ Thompson Feb 2018.
*
  *  This program is free software; you can redistribute it and/or modify
*  it under the terms of the GNU General Public License as published by
*  the Free Software Foundation; either version 2 of the License, or
*  (at your option) any later version.
*
  *  This program is distributed in the hope that it will be useful,
*  but WITHOUT ANY WARRANTY; without even the implied warranty of
*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*  GNU General Public License for more details.
*
  *  You should have received a copy of the GNU General Public License
*  along with this program; if not, a copy is available at
*  https://www.R-project.org/Licenses/
  */

  #ifdef HAVE_CONFIG_H
  # include <config.h>
  #endif

  #include <math.h>
  #include <string.h>  // memset, memcpy
  #include <R.h>
  #include <Rinternals.h>
  #include <Rmath.h>
  #include <R_ext/Lapack.h>        /* for Lapack (dpotrf, etc.) and BLAS */



/**
  * Simulate the Cholesky factor of a standardized Wishart variate with
* dimension p and nu degrees of freedom.
*
* @param nu degrees of freedom
* @param p dimension of the Wishart distribution
* @param upper if 0 the result is lower triangular, otherwise upper
triangular
* @param ans array of size p * p to hold the result
*
  * @return ans
*/
  static double
*std_rWishart_factor(double nu, int p, int upper, double ans[])
{
  /* Original code from R stats: rWishart.c - this function unaltered */
  int pp1 = p + 1;
  if (nu < (double) p || p <= 0)
    error("inconsistent degrees of freedom and dimension");

  memset(ans, 0, p * p * sizeof(double));
  for (int j = 0; j < p; j++) {	/* jth column */
      ans[j * pp1] = sqrt(rchisq(nu - (double) j));
      for (int i = 0; i < j; i++) {
        int uind = i + j * p, /* upper triangle index */
          lind = j + i * p; /* lower triangle index */
            ans[(upper ? uind : lind)] = norm_rand();
            ans[(upper ? lind : uind)] = 0;
      }
  }
  return ans;
}

/**
  * Simulate a sample of random matrices from a Wishart distribution -
  * inverse of Cholesky decomposition.
*
  * @param ns Number of samples to generate
* @param nuP Degrees of freedom
* @param scal Positive-definite scale matrix
*
  * @return
*/
  SEXP
rInvCholWishart(SEXP ns, SEXP nuP, SEXP scal)
{
  SEXP ans;
  int *dims = INTEGER(getAttrib(scal, R_DimSymbol)), info,
  n = asInteger(ns), psqr;
  double *scCp, *ansp, *tmp, nu = asReal(nuP), one = 1;

  if (!isMatrix(scal) || !isReal(scal) || dims[0] != dims[1])
    error("'scal' must be a square, real matrix");

  if (n <= 0) n = 1;
  // allocate early to avoid memory leaks in Callocs below.
  PROTECT(ans = alloc3DArray(REALSXP, dims[0], dims[0], n));
  psqr = dims[0] * dims[0];
  tmp = Calloc(psqr, double);
  scCp = Calloc(psqr, double);

  Memcpy(scCp, REAL(scal), psqr);
  memset(tmp, 0, psqr * sizeof(double));
  F77_CALL(dpotrf)("U", &(dims[0]), scCp, &(dims[0]), &info);
  if (info)
    error("'scal' matrix is not positive-definite");
  ansp = REAL(ans);
  GetRNGstate();
  for (int j = 0; j < n; j++) {
    double *ansj = ansp + j * psqr;
    std_rWishart_factor(nu, dims[0], 1, tmp);
    F77_CALL(dtrmm)("R", "U", "N", "N", dims, dims,
                    &one, scCp, dims, tmp, dims);

    /* Here we make the main change by omitting the A * A**T step */
    /* And inverting. Altered Feb 2018. */
    /* Original code from R stats: rWishart.c */

         F77_CALL(dtrtri)("U", "N", &(dims[1]), tmp,
                  &(dims[1]), &info);


    for (int i = 0; i < dims[0]; i++)
      for (int k = 0; k < dims[0]; k++)
        ansj[i + k * dims[0]] = tmp[i + k * dims[0]];


  }

  PutRNGstate();
  Free(scCp); Free(tmp);
  UNPROTECT(1);
  return ans;
}


  /**
  * Simulate a sample of random matrices from a Wishart distribution -
  * Cholesky decomposition.
  *
  * @param ns Number of samples to generate
  * @param nuP Degrees of freedom
  * @param scal Positive-definite scale matrix
  *
  * @return
  */
  SEXP
    rCholWishart(SEXP ns, SEXP nuP, SEXP scal)
    {
      SEXP ans;
      int *dims = INTEGER(getAttrib(scal, R_DimSymbol)), info,
        n = asInteger(ns), psqr;
      double *scCp, *ansp, *tmp, nu = asReal(nuP), one = 1;


      if (!isMatrix(scal) || !isReal(scal) || dims[0] != dims[1])
        error("'scal' must be a square, real matrix");
      if (n <= 0) n = 1;
      // allocate early to avoid memory leaks in Callocs below.
      PROTECT(ans = alloc3DArray(REALSXP, dims[0], dims[0], n));
      psqr = dims[0] * dims[0];
      tmp = Calloc(psqr, double);
      scCp = Calloc(psqr, double);

      Memcpy(scCp, REAL(scal), psqr);
      memset(tmp, 0, psqr * sizeof(double));
      F77_CALL(dpotrf)("U", &(dims[0]), scCp, &(dims[0]), &info);
      if (info)
        error("'scal' matrix is not positive-definite");
      ansp = REAL(ans);
      GetRNGstate();
      for (int j = 0; j < n; j++) {
        double *ansj = ansp + j * psqr;
        std_rWishart_factor(nu, dims[0], 1, tmp);
        F77_CALL(dtrmm)("R", "U", "N", "N", dims, dims,
                 &one, scCp, dims, tmp, dims);

        /* Here we make the main change by omitting the A * A**T step */
        /* Original code from R stats: rWishart.c Altered Feb 2018. */

        for (int i = 0; i < dims[0]; i++)
          for (int k = 0; k < dims[0]; k++)
            ansj[i + k * dims[0]] = tmp[i + k * dims[0]];


      }

      PutRNGstate();
      Free(scCp); Free(tmp);
      UNPROTECT(1);
      return ans;
    }
