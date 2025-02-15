# Concepts

This section is for anyone evaluating TigerBeetle, learning about it, or just curious.  It focuses
on the big picture --- what is the problem that TigerBeetle solves and why it looks nothing like a
typical SQL database from the outside _and_ from the inside.

- [OLTP](./oltp.md) defines the domain of TigerBeetle --- recording business transactions.
- [Debit-Credit](./debit-credit.md) argues that double-entry bookkeeping is the right schema for
  this domain.
- [Performance](./performance.md) explains how TigerBeetle can do a million transfers per second.
- [Safety](./safety.md) shows that safety and performance are not add odds with each other and that,
  on the contrary, an unprecedented level of safety can be achieved for OLTP.
