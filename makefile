# Frontend targets
frontend-install:
	cd Frontend && npm install

frontend-dev:
	cd Frontend && npm run dev

frontend-setup: frontend-install frontend-dev

# Backend targets
backend-install:
	cd Backend && npm install

backend-dev:
	cd Backend && npm run dev

backend-setup: backend-install backend-dev

# Full stack targets
install: frontend-install backend-install

dev:
	start /b cmd /c "cd Frontend && npm run dev"
	cd Backend && npm run dev

setup: install dev

# Default target
.PHONY: frontend-install frontend-dev frontend-setup backend-install backend-dev backend-setup install dev setup