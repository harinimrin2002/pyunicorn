# This file is part of pyunicorn.
# Copyright (C) 2008--2023 Jonathan F. Donges and pyunicorn authors
# URL: <http://www.pik-potsdam.de/members/donges/software>
# License: BSD (3-clause)
#
# Please acknowledge and cite the use of this software and its authors
# when results are used in publications or published elsewhere.
#
# You can use the following reference:
# J.F. Donges, J. Heitzig, B. Beronov, M. Wiedermann, J. Runge, Q.-Y. Feng,
# L. Tupikina, V. Stolbova, R.V. Donner, N. Marwan, H.A. Dijkstra,
# and J. Kurths, "Unified functional network and nonlinear time series analysis
# for complex systems science: The pyunicorn package"

cimport cython

import numpy as np
from numpy cimport ndarray

from ...core._ext.types import LAG, FIELD, DFIELD, INT32TYPE
from ...core._ext.types cimport LAG_t, FIELD_t, DFIELD_t, INT32TYPE_t

# coupling_analysis ===========================================================

def _symmetrize_by_absmax(
    ndarray[FIELD_t, ndim=2, mode='c'] similarity_matrix not None,
    ndarray[LAG_t, ndim=2, mode='c'] lag_matrix not None, int N):

    cdef:
        int i, j

    # loop over all node pairs
    for i in range(N):
        for j in range(N):
            # calculate max and argmax by comparing to
            # previous value and storing max
            if abs(similarity_matrix[i,j]) > abs(similarity_matrix[j,i]):
                similarity_matrix[j,i] = similarity_matrix[i,j]
                lag_matrix[j,i] = -lag_matrix[i,j]

            else:
                similarity_matrix[i,j] = similarity_matrix[j,i]
                lag_matrix[i,j] = -lag_matrix[j,i]

    return similarity_matrix, lag_matrix


def _cross_correlation_max(
    ndarray[FIELD_t, ndim=3, mode='c'] array not None,
    int N, int tau_max, int corr_range):

    cdef:
        ndarray[FIELD_t, ndim=2, mode='c'] similarity_matrix = np.ones(
            (N, N), dtype=FIELD)
        ndarray[LAG_t, ndim=2, mode='c'] lag_matrix = np.zeros(
            (N, N), dtype=LAG)
        double crossij, max
        int i, j, tau, k, argmax

    # loop over all node pairs, NOT symmetric due to time shifts!
    for i in range(N):
        for j in range(N):
            if i != j:
                max = 0.0
                argmax = 0
                # loop over taus INCLUDING the last tau value
                for tau in range(tau_max + 1):
                    crossij = 0
                    # here the actual cross correlation is calculated
                    # assuming standardized arrays
                    for k in range(corr_range):
                        crossij += array[tau,i,k] * array[tau_max,j,k]
                    # calculate max and argmax by comparing to
                    # previous value and storing max
                    if abs(crossij) > abs(max):
                        max = crossij
                        argmax = tau
                similarity_matrix[i,j] = <FIELD_t> (max / corr_range)
                lag_matrix[i,j] = <LAG_t> (tau_max - argmax)

    return similarity_matrix, lag_matrix


def _cross_correlation_all(
    ndarray[FIELD_t, ndim=3, mode='c'] array not None,
    int N, int tau_max, int corr_range):

    cdef:
        int i, j, tau, k
        double crossij
        ndarray[FIELD_t, ndim=3, mode='c'] lagfuncs = np.zeros(
            (N, N, tau_max+1), dtype=FIELD)

    # loop over all node pairs, NOT symmetric due to time shifts!
    for i in range(N):
        for j in range(N):
            # loop over taus INCLUDING the last tau value
            for tau in range(tau_max + 1):
                crossij = 0
                # here the actual cross correlation is calculated
                # assuming standardized arrays
                for k in range(corr_range):
                    crossij += array[tau,i,k] * array[tau_max,j,k]

                lagfuncs[i,j,tau_max-tau] = <FIELD_t> (crossij / corr_range)

    return lagfuncs


def _get_nearest_neighbors(
        ndarray[FIELD_t, ndim=1, mode='c'] array not None,
        int T, int dim_x, int dim_y, int k, int dim):

    # Initialize
    cdef:
        int i, j, index=0, t, m, n, d, kxz, kyz, kz
        ndarray[INT32TYPE_t, ndim=1, mode='c'] indexfound = np.zeros(
            T, dtype=INT32TYPE)
        double dz=0., dxyz=0., dx=0., dy=0., eps, epsmax
        ndarray[DFIELD_t, ndim=1, mode='c'] dist = np.zeros(
            (T*dim), dtype=DFIELD)
        ndarray[DFIELD_t, ndim=1, mode='c'] dxyzarray = np.zeros(
            (k+1), dtype=DFIELD)
        ndarray[INT32TYPE_t, ndim=1, mode='c'] k_xz = np.zeros(
            T, dtype=INT32TYPE)
        ndarray[INT32TYPE_t, ndim=1, mode='c'] k_yz = np.zeros(
            T, dtype=INT32TYPE)
        ndarray[INT32TYPE_t, ndim=1, mode='c'] k_z = np.zeros(
            T, dtype=INT32TYPE)

    # Loop over time
    for i in range(T):
        # Growing cube algorithm: Test if n = #(points in epsilon-
        # environment of reference point i) > k
        # Start with epsilon for which 95% of points are inside the cube
        # for a multivariate Gaussian
        # eps increased by 2 later, also the initial eps
        eps = (k/T)**(1./dim)

        # n counts the number of neighbors
        n = 0
        while n <= k:
            # Increase cube size
            eps *= 2.
            # Start with zero again
            n = 0
            # Loop through all points
            for t in range(T):
                d = 0
                while (d < dim) and (abs(array[d*T + i]
                                     - array[d*T + t]) < eps):
                    d += 1

                # If all distances are within eps, the point t lies
                # within eps and n is incremented
                if d == dim:
                    indexfound[n] = t
                    n += 1

        # Calculate distance to points only within epsilon environment
        # according to maximum metric
        for j in range(n):
            index = indexfound[j]

            # calculate maximum metric distance to point
            dxyz = 0.
            for d in range(dim):
                dist[d*T + j] = abs(array[d*T + i] - array[d*T + index])
                dxyz = max(dist[d*T + j], dxyz)

            # insertion-sort current distance into 'dxyzarray'
            # if it is among the currently smallest k+1 distances 
            if j == 0:
                dxyzarray[j] = dxyz
            else:
                m = min(k, j-1)
                # go through previously sorted smallest distances and
                # if it is smaller than any, find slot for current distance 
                while (m >= 0) and (dxyz < dxyzarray[m]):
                    # if it's not in the last slot already,
                    # move previously found distance to the right
                    if not m == k:
                        dxyzarray[m+1] = dxyzarray[m]
                    m -= 1

                # sort in, if a slot was found
                if not m == k:
                    dxyzarray[m+1] = dxyz

        # Epsilon of k-th nearest neighbor in joint space
        epsmax = dxyzarray[k]

        # Count neighbors within epsmax in subspaces, since the reference
        # point is included, all neighbors are at least 1
        kz = 0
        kxz = 0
        kyz = 0
        for j in range(T):

            # X-subspace
            dx = abs(array[0*T + i] - array[0*T + j])
            for d in range(1, dim_x):
                dist[d*T + j] = abs(array[d*T + i] - array[d*T + j])
                dx = max(dist[d*T + j], dx)

            # Y-subspace
            dy = abs(array[dim_x*T + i] - array[dim_x*T + j])
            for d in range(dim_x, dim_y):
                dist[d*T + j] = abs(array[d*T + i] - array[d*T + j])
                dy = max(dist[d*T + j], dy)

            # Z-subspace, if empty, dz stays 0
            dz = 0.
            for d in range(dim_x+dim_y, dim):
                dist[d*T + j] = abs(array[d*T + i] - array[d*T + j])
                dz = max(dist[d*T + j], dz)

            # For no conditions, kz is counted up to T
            if dz < epsmax:
                kz += 1
                if dx < epsmax:
                    kxz += 1
                if dy < epsmax:
                    kyz += 1

        # Write to numpy arrays
        k_xz[i] = kxz
        k_yz[i] = kyz
        k_z[i] = kz
        
    return k_xz, k_yz, k_z
