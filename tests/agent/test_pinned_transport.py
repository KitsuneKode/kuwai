"""Exercise the actual HTTP connector with fake DNS/sockets, never the network."""
import socket
import sys
from pathlib import Path
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[2]/'bin'))
import rice_agent as agent

@pytest.fixture
def transport(monkeypatch):
    monkeypatch.delenv('RICE_FETCH_ALLOW_LOCAL', raising=False)
    class FakeSocket:
        peer = '8.8.8.8'
        def __init__(self, *args): self.connected=[]; self.closed=False
        def settimeout(self, timeout): pass
        def connect(self, addr): self.connected.append(addr)
        def getpeername(self): return (self.peer,443)
        def close(self): self.closed=True
    sockets=[]
    def new_socket(*args):
        value=FakeSocket(*args); sockets.append(value); return value
    monkeypatch.setattr(socket,'socket',new_socket)
    return FakeSocket,sockets


def test_approved_hostname_cannot_rebind_to_private_at_connect(monkeypatch,transport):
    _, sockets = transport
    answers = iter(['8.8.8.8','127.0.0.1'])
    monkeypatch.setattr(socket,'getaddrinfo',lambda *a,**k: [(socket.AF_INET,socket.SOCK_STREAM,6,'',(next(answers),443))])
    agent.check_public('https://fixture.invalid')
    with pytest.raises(agent.BlockedURL):
        agent._PinnedHTTPS('fixture.invalid').connect()
    assert sockets == []  # Refused before a private socket was even created.


@pytest.mark.parametrize('peer',['127.0.0.1','::1','10.0.0.1','169.254.1.1'])
def test_connected_peer_is_rechecked_and_socket_closed(monkeypatch,transport,peer):
    kind,sockets=transport; kind.peer=peer
    monkeypatch.setattr(socket,'getaddrinfo',lambda *a,**k: [(socket.AF_INET,socket.SOCK_STREAM,6,'',('8.8.8.8',443))])
    with pytest.raises(agent.BlockedURL):
        agent._pinned_socket('fixture.invalid',443,1)
    assert len(sockets)==1 and sockets[0].closed


def test_connector_uses_the_validated_numeric_address(monkeypatch,transport):
    _,sockets=transport; calls=[]
    def resolve(*a,**k):
        calls.append(a); return [(socket.AF_INET,socket.SOCK_STREAM,6,'',('8.8.8.8',443))]
    monkeypatch.setattr(socket,'getaddrinfo',resolve)
    value=agent._pinned_socket('fixture.invalid',443,1)
    assert len(calls)==1 and value.connected==[('8.8.8.8',443)]
    assert sockets==[value]
