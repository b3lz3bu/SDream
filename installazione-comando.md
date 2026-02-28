# Installare SDream come comando di sistema

Questa guida spiega come rendere SDream disponibile come comando globale, in modo da poterlo richiamare da qualsiasi posizione nel terminale semplicemente scrivendo:

```bash
sdream set-sd /media/utente/sd
sdream list
sudo sdream menu
```

Esistono due metodi. Il **Metodo A** è quello consigliato perché non richiede permessi di root e funziona su qualsiasi distribuzione Linux.

---

## Metodo A — Installazione per l'utente corrente (consigliato)

Copia lo script in `~/.local/bin`, una cartella dedicata ai programmi personali dell'utente che nelle distribuzioni moderne è già inclusa nel `PATH`.

```bash
# 1. Crea la cartella se non esiste ancora
mkdir -p ~/.local/bin

# 2. Copia lo script rinominandolo senza estensione
cp ~/SDream/sdream.sh ~/.local/bin/sdream

# 3. Rendilo eseguibile
chmod +x ~/.local/bin/sdream
```

Verifica che `~/.local/bin` sia nel tuo `PATH`:

```bash
echo $PATH
```

Se nell'output compare `...:/home/tuoutente/.local/bin:...` sei a posto e puoi passare direttamente alla sezione **Verifica**.

Se non compare, aggiungila manualmente. Apri il file di configurazione della tua shell:

```bash
# Per bash (il default sulla maggior parte delle distro)
nano ~/.bashrc

# Per zsh
nano ~/.zshrc
```

Aggiungi questa riga in fondo al file:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Salva (`Ctrl+O`, `Invio`, `Ctrl+X`) e ricarica la configurazione:

```bash
source ~/.bashrc
# oppure, se usi zsh:
source ~/.zshrc
```

---

## Metodo B — Installazione di sistema (per tutti gli utenti)

Se volete rendere il comando disponibile a tutti gli utenti della macchina, copiate lo script in `/usr/local/bin`, che è la posizione standard per i programmi locali su sistemi Unix.

```bash
sudo cp ~/SDream/sdream.sh /usr/local/bin/sdream
sudo chmod +x /usr/local/bin/sdream
```

Questo metodo richiede `sudo` una volta sola durante l'installazione, dopodiché il comando `sdream` è disponibile globalmente senza ulteriori configurazioni.

---

## Verifica

Aprite un nuovo terminale (o ricaricate la shell come indicato sopra) e provate:

```bash
# Deve restituire il percorso dove è installato lo script
which sdream

# Deve mostrare la guida dei comandi
sdream help
```

Se `which sdream` restituisce il percorso corretto, l'installazione è riuscita.

---

## Aggiornare SDream in futuro

Quando esce una nuova versione dello script basta sovrascrivere il file installato:

```bash
# Metodo A (utente corrente)
cp ~/SDream/sdream.sh ~/.local/bin/sdream

# Metodo B (sistema)
sudo cp ~/SDream/sdream.sh /usr/local/bin/sdream
```

Non è necessario toccare nulla altro: il comando `sdream` continuerà a funzionare con la nuova versione.

---

## Nota su sudo

I comandi `sdream init` e `sdream menu` richiedono privilegi di root. Con l'installazione globale (Metodo B) si richiamano esattamente come prima:

```bash
sudo sdream init
sudo sdream menu
```

SDream riconosce automaticamente l'utente reale anche quando viene eseguito con `sudo`, quindi la configurazione (percorso SD) salvata con il vostro utente normale viene letta correttamente.
