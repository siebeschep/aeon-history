# Aeon – The History of Everything

Statische website (HTML/JS) + Supabase (login, database, beheerdersrechten). Geen build nodig.

## Opzetten
Project "Knowly": schema, lessen en `config.js` zijn al ingesteld (stap 1–3 gedaan).
4. **Lokaal testen:** `python3 -m http.server 8000` in deze map → http://localhost:8000 (niet via file://).
5. **Hosten:** zet de map op Netlify (drag & drop), Cloudflare Pages of GitHub Pages.
6. **Supabase → Authentication → URL Configuration:** vul je site-URL in als *Site URL* (en lokaal evt. als Redirect URL).

## Jezelf beheerder maken
1. Maak op de site een account en bevestig je e-mail (of zet "Confirm email" uit in Authentication → Providers → Email).
2. Voer in de SQL Editor uit (met jouw e-mailadres):
```sql
insert into public.user_roles (user_id, role)
select id, 'admin' from auth.users where email = 'JOUW_EMAIL';
```
3. Herlaad de site: tabblad **Admin** verschijnt. Daar kun je lessen toevoegen, bewerken en verwijderen (EN, NL of beide).

## Hoe het werkt
- Iedereen (ook uitgelogd) leest de lessen. Voortgang, XP en streak worden alleen bewaard voor ingelogde gebruikers (tabellen `progress` en `stats`, per gebruiker afgeschermd).
- Alleen gebruikers met rol `admin` kunnen `chapters` en `lessons` wijzigen. Rollen kunnen niet via de website geschreven worden.
