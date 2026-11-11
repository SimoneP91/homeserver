# LocalClima sul server

Guida completa (installazione, copia dei segreti dal vecchio PC, associazione dei TV,
aggiornamenti): [docs/05-app.md](../../docs/05-app.md).

| File / percorso                         | Cosa                                                                 |
| --------------------------------------- | -------------------------------------------------------------------- |
| `backend.env.example` (qui)              | da copiare in `/srv/apps/localclima/backend/.env`: porta 8100 su loopback, mDNS spento |
| `infra/caddy/sites/localclima.caddy`     | `http://localclima.local` → `127.0.0.1:8100`                          |
| `infra/mdns/aliases`                     | contiene `localclima`: il nome lo pubblica il server                  |
| `/srv/apps/localclima`                   | clone del repository di LocalClima (produzione)                       |
| `/srv/apps/localclima/backend/devices.yaml` | dispositivi, token e chiavi: copiato a mano dal vecchio PC, mai in git |
| volume Docker `localclima_localclima-data` | log (`/data/localclima.log`) e IP trovati in rete: si ricostruiscono da soli, fuori dal backup |
