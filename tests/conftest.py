"""
What every test starts from (2.1.49): the Library's album lists kept from Navidrome's answers
(src/index_keep.py) are kept by a clock, for whoever asks - so a list one test read would answer the next
test's ask for the same person and scope. Dropped, and the library settled, before each.
"""

import pytest

from src import index_keep


@pytest.fixture(autouse=True)
def no_album_list_kept():
    index_keep.reset()
    yield
    index_keep.reset()
