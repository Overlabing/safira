# One website data store per Profile, shared by its Spaces

The Profile is the security boundary; a Space is only organisation. Every Space of a Profile uses that Profile's data store, so logins carry across its Spaces as in Arc and Zen. We rejected one data store per Space because each Space would need its own logins and would become a small Profile. Changing this later means migrating user cookies and storage, so the choice is hard to reverse.
