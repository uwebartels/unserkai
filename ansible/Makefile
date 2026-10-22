ANSIBLE_PLAYBOOK ?= ansible-playbook
ANSIBLE          ?= ansible
INVENTORY        ?= inventory/hosts.yml
PLAYBOOK         ?= playbooks/site.yml
TAGS             ?=
LIMIT            ?=

.PHONY: help deps syntax lint ping check deploy deploy-limit

help:
	@echo "make deps          Ansible-Collections installieren"
	@echo "make syntax        Playbooks auf Syntax pruefen"
	@echo "make lint          ansible-lint ausfuehren"
	@echo "make ping          SSH-Verbindung zu allen Hosts testen"
	@echo "make check         Dry-Run mit --check --diff"
	@echo "make deploy        Konfiguration anwenden"
	@echo "make deploy-limit  Nur einen Host konfigurieren (LIMIT=ws-01)"
	@echo "Optional: TAGS=users,docker einschraenken"

deps:
	ansible-galaxy collection install -r requirements.yml

syntax:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) --syntax-check $(PLAYBOOK)

lint:
	ansible-lint

ping:
	$(ANSIBLE) all -i $(INVENTORY) -m ansible.builtin.ping

check:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) --check --diff $(if $(TAGS),--tags $(TAGS),) $(PLAYBOOK)

deploy:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) $(if $(TAGS),--tags $(TAGS),) $(PLAYBOOK)

deploy-limit:
	$(ANSIBLE_PLAYBOOK) -i $(INVENTORY) --limit $(LIMIT) $(if $(TAGS),--tags $(TAGS),) $(PLAYBOOK)
