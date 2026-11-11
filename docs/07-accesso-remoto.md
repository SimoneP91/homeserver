# 7. Accesso remoto con Tailscale (facoltativo)

Per usare le app e SSH da fuori casa, senza aprire nulla sul router.

## Perché non aprire porte sul router

- Le app di casa non hanno login: LocalClima, esposto su Internet, darebbe a chiunque il controllo
  di condizionatori e TV. Ogni porta aperta viene scansionata da bot in pochi minuti.
- Servirebbe configurare il router (proprio quello da cui non vogliamo dipendere), un DNS dinamico
  per l'IP pubblico che cambia e certificati; con molti operatori (CGNAT) non funzionerebbe nemmeno.

[Tailscale](https://tailscale.com) crea una rete privata cifrata (WireGuard) tra i tuoi
dispositivi: il server non apre porte verso Internet, funziona anche dietro CGNAT e il piano
personale è gratuito.

## Installare

1. Sul server, rilancia il bootstrap con l'opzione (non tocca il resto):

   ```sh
   sudo bash /srv/homeserver/scripts/bootstrap.sh --tailscale
   sudo tailscale up --accept-dns=false
   ```

   `tailscale up` stampa un link: aprilo sul PC e accedi (Google, Microsoft, GitHub…).
   `--accept-dns=false` lascia al server il DNS del router: il server non ha bisogno di risolvere i
   nomi della rete Tailscale e così Docker non ne risente.
2. Nella console di amministrazione (<https://login.tailscale.com/admin/machines>), sul server:
   *… → Disable key expiry*, altrimenti dopo 180 giorni esce dalla rete e va riautenticato.
3. Installa l'app **Tailscale** su telefono (iPhone o Android) e PC Windows e accedi con lo stesso
   account.

Il firewall accetta tutto ciò che arriva dall'interfaccia `tailscale0`, cioè solo dai tuoi
dispositivi.

## Raggiungere il server: MagicDNS

Con **MagicDNS** (attivo di default; *DNS* nella console) ogni dispositivo ha un nome: il server è
`casa`, o per esteso `casa.<nome-tailnet>.ts.net` (il nome della tailnet è nella pagina *DNS*).

SSH da fuori casa, dal PC con Tailscale acceso:

```powershell
ssh -o HostName=casa casa
```

oppure aggiungi a `C:\Users\<te>\.ssh\config` un secondo host che usa la stessa impronta:

```text
Host casa-ts
    HostName casa
    User <utente>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    HostKeyAlias casa
    ServerAliveInterval 30
    ServerAliveCountMax 4
```

e poi `ssh casa-ts` (anche da VS Code Remote-SSH).

## Raggiungere le app: Tailscale Serve

I nomi `.local` funzionano solo nella rete di casa, e Caddy sceglie l'app in base al nome. Da
fuori si usa **Tailscale Serve**, che pubblica un'app **solo dentro la tua rete Tailscale**, in
HTTPS con un certificato valido.

1. Nella console, *DNS → HTTPS Certificates → Enable*.
2. Sul server, una porta HTTPS per app:

   ```sh
   sudo tailscale serve --bg --https=443 http://127.0.0.1:8100     # LocalClima
   sudo tailscale serve --bg --https=8443 http://127.0.0.1:3001    # Uptime Kuma
   sudo tailscale serve status
   ```

3. Dal telefono, con Tailscale attivo:
   - LocalClima: `https://casa.<nome-tailnet>.ts.net`
   - Uptime Kuma: `https://casa.<nome-tailnet>.ts.net:8443`

La configurazione resta attiva anche dopo i riavvii. Per toglierla tutta:
`sudo tailscale serve reset`.

Vantaggio in più: in HTTPS LocalClima si installa come vera app (PWA) anche su Android. Dockge è
meglio non pubblicarlo: da fuori casa basta SSH.

**Funnel no.** `tailscale funnel` pubblicherebbe l'app su Internet per chiunque: non usarlo per le
app di casa.

Avanti: [8. Manutenzione](08-manutenzione.md).
