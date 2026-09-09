#!/usr/bin/env bash
# lib-git-credenciales.sh — Credenciales de git para los scripts de la fábrica.
#
# No se ejecuta solo: se carga desde otro script.
#     source "$(dirname "$0")/lib-git-credenciales.sh"
#
# Existe porque la misma corrección se escribió dos veces en dos scripts, y la
# segunda vez se olvidó — el script se colgó pidiendo un usuario por teclado en
# medio de una ejecución desatendida. Un fragmento repetido es un fragmento que
# tarde o temprano diverge.
#
# Qué hace:
#   - GIT_TERMINAL_PROMPT=0 para que git NUNCA pida credenciales por teclado.
#     Sin esto, un script desatendido se queda colgado en lugar de fallar.
#   - Si hay GITHUB_TOKEN, lo pasa por un askpass efímero que se borra al salir,
#     de modo que el token no queda escrito en el .git/config de ningún clon.

export GIT_TERMINAL_PROMPT=0

if [ -n "${GITHUB_TOKEN:-}" ]; then
  _IAGENCY_ASKPASS="$(mktemp)"
  cat > "$_IAGENCY_ASKPASS" <<'EOS'
#!/bin/sh
case "$1" in
  Username*) echo "x-access-token" ;;
  Password*) echo "$GITHUB_TOKEN" ;;
esac
EOS
  chmod 700 "$_IAGENCY_ASKPASS"
  export GIT_ASKPASS="$_IAGENCY_ASKPASS"
  trap 'rm -f "$_IAGENCY_ASKPASS"' EXIT
  echo "Credenciales: usando GITHUB_TOKEN."
else
  echo "AVISO: sin GITHUB_TOKEN. Los repositorios privados no serán accesibles."
  echo "       Carga tus secretos con:  source ~/.iagency-env"
fi
