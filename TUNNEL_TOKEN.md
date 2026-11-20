# Tunel Cloudflare `victus` – przekazanie innej osobie

Plik `.cloudflared/victus.token` to dane uwierzytelniające tunel `victus`. Jest objęty `.gitignore` – **nigdy nie trafia do repozytorium**. Przekazuj go prywatnie; kto go ma, może używać tunelu.

## Wariant 1: przekazujesz cały folder projektu

Folder zawiera `.cloudflared\cloudflared.exe` oraz `.cloudflared\victus.token`. Osoba uruchamia:

```
run_server_and_tunnel.bat
```

Skrypt `server_control.ps1` sam odpali serwer Python na porcie 8081 i tunel z tokenu (chyba że na komputerze jest już usługa Windows `Cloudflared` – wtedy korzysta z niej).

## Wariant 2: osoba klonuje repozytorium z Git

1. `git clone <repo>` i wejdź do folderu.
2. Wklej otrzymany plik do `.cloudflared\victus.token`.
3. Jeśli nie ma `.cloudflared\cloudflared.exe`, zainstaluj cloudflared:
   ```
   winget install --id Cloudflare.cloudflared
   ```
   (albo skopiuj plik `cloudflared.exe` z przekazanego folderu).
4. Uruchom `run_server_and_tunnel.bat`.

## Uwagi

- Port `8081` musi być wolny, a Python dostępny w `PATH`.
- Adres publiczny: `https://sale.pwojtaszek.5g.in`.
- `server_control.ps1 -Action stop` zatrzymuje serwer i ewentualny tunel uruchomiony z tokenu, ale nie zatrzymuje usługi Windows `Cloudflared` (może obsługiwać inne aplikacje).
- Jeśli token wycieknie, wygeneruj nowy w panelu Cloudflare: **Zero Trust → Networks → Tunnels → victus → Rotate token**, a potem zastąp plik `victus.token`.
