#!/bin/bash
set -e

echo "Installing Melos..."
dart pub global activate melos 6.1.0

echo "Bootstrapping monorepo..."
melos bootstrap

if [ ! -f .env ]; then
  echo "Copying .env.example to .env..."
  cp .env.example .env
  echo "Please update .env with your Supabase credentials."
fi

echo "Bootstrap complete!"
