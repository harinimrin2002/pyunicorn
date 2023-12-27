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

"""
Simple tests for the JointRecurrencePlot class.
"""

import numpy as np

import pytest

from pyunicorn.timeseries import JointRecurrencePlot
from pyunicorn.funcnet import CouplingAnalysis


@pytest.mark.parametrize("n", [2, 10, 50])
def test_recurrence(metric: str, n: int):
    ts = CouplingAnalysis.test_data()[:n, 0]
    jrp = JointRecurrencePlot(ts, ts, threshold=(.1, .1),
                              metric=(metric, metric))
    dist = {
        i: jrp.distance_matrix(getattr(jrp, f"{i}_embedded"), metric=metric)
        for i in "xy"}
    assert all(d.shape == (n, n) for d in dist.values())
    assert np.allclose(*dist.values())
    assert jrp.recurrence_matrix().shape == (n, n)
