#!/usr/bin/env bash
# Bypass homebrew git-foil wrapper and run tests directly

export PATH="/Users/kaitaylor/.asdf/installs/elixir/1.18.4-otp-28/bin:/Users/kaitaylor/.asdf/installs/erlang/28.1/bin:/usr/bin:/bin"
cd /Users/kaitaylor/Documents/Coding/git-foil
exec /Users/kaitaylor/.asdf/installs/elixir/1.18.4-otp-28/bin/elixir /Users/kaitaylor/.asdf/installs/elixir/1.18.4-otp-28/bin/mix test "$@"
