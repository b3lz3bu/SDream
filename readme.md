##### SDream V 1.0 by rymstudio 

SDream è un script bash che vi permette di creare/gestire archivi di giochi/rom per Sega Dreamcast da utilizzira su GDEMU attraverso una memoria di archiviazione SD.

**Cosa è GDEMU ?** GDEMU è una periferica hardware che va a sostituire in tolo la lente di lettura dei dischi Dreamcast a bordi di quest'ultimo, i vostri GD-Rom potrenno essere utilizzati come immagini direttamente archiviate su una memoria esterna di tipo SD.

![gdemu](/home/emanuele/SDream/guida/gdemu.png)

Questa periferica è facilmente acquistabili sui principali shop online di elettronica e non solo, il costo è tutto sommato contenuto, l'installazione è semplicissima e non è necessario procedere con saldature di alcun genere, tutto si fa collegando il flat cable e la scheda si fissa con dei supporti in plastica semplicemente a pressione.

**Come funziona GDEMU ?** Una volta installato sul nostro Dreamcast GDEMU ingannerà la console facendole credere di essere un lettore CD/GDI e facendo partire il software necessario per la gestione della memoria SD e delle ISO/ROM che andremo a caricare. Questo è molto molto comodo per non strassare con il continuo utilizzo i vostri giochi Dreamcast, potrete giocare quindi la vostra copia di backup liberi dal fastidioso inserisci, apri, chiudi etc etc...

**A che serve SDream ?** Bella domanda! SDream è uno strumento utile a inizializzare, creare e gestire le cartelle con le vostre rom all'interno della SD che andremo ad utilizzare su GDEMU, non basta infatti copiare *a caso* i giochi sulla scheda di memoria, GDEMU richiede infatti una precisa organizzazione dei file di gioco e questo strumento cerca di aiutarvi in tal senso.
Esistono alcuni tool per Windows ma non ho trovato nulla di davvero funzionante in ambiente Linux, nonostante le ricerche restituiscano risultati i tool disponibili, forsa per mia mancanza non so, sono risultati non funzionanti, o peggio, versioni Windows malamente rimaneggiate che necessiatano di librerire Microsoft per funzionare.
Analizzato il funzionamento del tool GD-SDMaker per Windows ho immaginato di poterlo realizzare in maniera naloga anche su Linux, non sono uno sviluppatore e mi sono barcamenato per farlo utilizzando la bash di Linux. Questo ha portato a dei compromessi, ovviamente, anche se ho provato, non sono riuscito a donare allo strumento un aspetto grafico, il tutto funziona in fatto dal terminale.

![sdream_v10_scr001](/home/emanuele/SDream/guida/sdream_v10_scr001.png)

**Installazione e compatibilità** SDream è fondamentalmente uno script che si occupa di *organizzare* la scheda SD per GDEMU, in parte questa operazione potrebbe essere realizzata anche manualmente, conoscendo lo standard di nomenclatura, file ed organizzazione degli stessi come richiesto da GDEMU, tuttavia questa operazione  potrebbe rivelarsi lunga e noiosa e proprio per la quantità di *cosette* da sistemare sensibile ad errori anche solo che di digitazione, un robot che lo fa per noi ci può far risparmiare fatica e tempo, tempo da reimpiegare a giocare con il Dreamcast.

Ho *sviluppato* questo strumento su piattaforma Debian Like, per la precisione su Linux Mint, ne ho testato la compatibilità su sistemi Ubuntu, Pop-OS e Debian (con *sudo* abilitato), è necessario utilizzare questo script con privilegio di amministrazione ***sudo*** su sistemi Debian based, perché alcune operazioni/istruzioni hanno necessità di permessi di root per funzionare. In particolare le funzioni ***init*** e ***menu*** che si occupano rispettivamente della inizializzazione della scheda di memoria SD e della rigenerazione del menu di selezione dei giochi in essa contenuti.

Per funzionare SDream ha bisogno di alcuno tool e file esterni, vediamo quali:

- ***genisoimage*** uno strumento per la creazione di file *.ISO con la possibilità di settare differenti parametri, a questo link potete trovare maggiori informazioni in merito: https://linux.die.net/man/1/genisoimage Lo script ne rileverà o meno la presenza ed in caso non sia presente procederà all'installazione con ***Apt***, sono richiesti i privilegi di root

- ***GDMENU*** il file *gdmenu.tar.gz* contiene i file necessari per il boot ed il caricamento del menu di selezione dei titoli all'avvio su Dreamcast deve essere scaricato e trovarsi nelle stessa cartella dello scritp *./sdream.sh* . Potete recuperarlo con un semplice *wget* 

  ```
  wget https://www.rymstudio.it/sdream/gdmenu.tar.gz
  ```

Per maggiore comodità di seguito mi permetto di inserire una serie di comandi per velocizzare l'installazione ed il recupero di tutti i file necessari per il funzionamento di SDream:

```
#!/bin/bash

echo "creao cartella"
mkdir sdream
cd sdream

echo "installazione Sdream"

echo "scarico GDEMU da rymstudio.it"
wget https://www.rymstudio.it/sdream/gdmenu.tar.gz

echo "scarico SDream da rymstudio.it"
wget https://www.rymstudio.it/sdream/sdream.tar.gz

echo "installo genisoimage dai repository del tuo sistema"
apt install genisoimage -y

echo "scomprimo l'archivio di SDream."
tar -xzvf sdream.tar.gz

echo "rendo eseguibile SDream"
chmod +x sdream.sh
rm sdream.tar.gz

echo "finito!"
```

questo è uno script per la bash, che ho volutamente resto super semplice, potete anche eseguire i comandi singolarmente, salvo gli *echo* che in quel caso servirebbero a poco

***Come utilizzare SDream*** 

Se lanciate il comando ./sdream.sh senza alcun parametro o con lo switch -help otterrete questo output a video:

```
SDREAM -  Games Manager v1.0
Gestione minimale per file immagine Dreamcast per GDEMU

Comandi:
  set-sd <percorso>              Imposta la directory della SD Card
  scan                           Scansiona la SD Card
  init                           Inizializza la SD Card con GDMenu
  list                           Mostra la lista dei giochi
  add <file> [numbered]          Aggiunge un gioco
  add-folder <dir> [numbered]    Aggiunge tutti i giochi da una cartella
  remove <numero>                Rimuove un gioco
  rename <numero> "Nome"         Rinomina un gioco
  reorder                        Riordina numericamente le cartelle
  numbered                       Converte cartelle in formato numerico
  menu                           Rigenera il menu GDMenu
  help                           Mostra questa guida

Esempi:
  ./dreamsd_gdemu.sh set-sd /media/sdcard
  ./dreamsd_gdemu.sh init
  ./dreamsd_gdemu.sh add-folder /path/games true
  sudo ./dreamsd_gdemu.sh menu

Note:
  - I file vengono rinominati in 'disc.estensione' per compatibilità GDEMU
  - La cartella 01 è riservata per GDMenu
  - I comandi 'menu' e 'init' richiedono privilegi sudo
  - Richiesti: genisoimage o mkisofs per creare file ISO

```



**set-sd** definisce il percorso di mount della scheda SD per la sessione di lavoro con SDream, una volta settato il percorso quella sarà la cartella di lavoro dove verranno scritti o modificati i file. La scheda SD secondo le specifiche di GDEMU deve essere formattata con filesystem FAT32, questa operazione non è inclusa nel comanto ***set-sd*** 

```
.sdream setsd /media/utente/nome_sd
```



***scan*** esegue una scnasione del contenuto della scheda  SD al percorso di mount settato con *set-sd*.Di seguito un esempio di output:

```
SD Card impostata: /media/utente/nome_sd
Scansione della SD Card in corso...
Scansione (11/12): .Trash-1000
Trovati 10 giochi nella SD Card.

```



**init** questo switch, richiede che sdream sia lanciato con ***sudo*** (permessi di roo), inizializza e prepara la scheda SD per il boot su GDEMU con la cartella **01** contenente GD-Menu il software Dreamcast per la gestione dei file di gioco (ROM) caricati sulla scheda.



**list** mostra la lista dei giochi/file/rom contenuti nella scheda SD, esempio di output:

```
#     TITOLO                                   DIMENSIONE TIPO  
----------------------------------------------------------------------
01    disc                                     1 MB       GDI   
02    GigaWing v1.000 (2000)(Capcom)(US)[!]    1 GB       GDI   
03    Soul Calibur v1.000 (1999)(Namco)(US)[   1 GB       GDI   
04    Street Fighter III - 3rd Strike v1.001   1 GB       GDI   
05    Street Fighter Alpha 3 v1.001 (2000)(C   1 GB       GDI   
06    Fatal Fury - Mark of the Wolves v0.800   1 GB       GDI   
07    Marvel vs. Capcom - Clash of Super Her   1 GB       GDI   
08    Wacky Races v1.001 (2000)(Infogrames)(   1 GB       GDI   
09    Sword of the Berserk - Guts' Rage v1.0   1 GB       GDI   
10    WIPEOUT                                  706 MB     CDI   

```



**add** aggiunge un file di gioco/ROM alla scheda SD

```
./sdream.sh add /home/utente/giochidreamcast/gioco_che_voglio_aggiungere.estensione-supportata
```

questo comando aggiungerà il gioco indicato alla cartella/scheda SD con numerazione progressiva. Se viene aggiunto un gico è necessario rigenerare il *menu* con lo switch di riferimento.



**add-folder** questo comando aggiungerà il contenuto di un'intera cartella alla memoria SD, lo script analizza e rileva i file supportato e li riorganizza in un albero di cartelle utile a GDEMU.

```
./sdream.sh add-folder /home/utente/miei_giochi_dreamcast
```



**remove** comando che rimuove dalla scheda di memoria SD un gioco indicando la numerazione dello stesso.
dopo l'esecuzione è raccomandato eseguire il comando *menu* pee ricostruire il menu di selezione dei giochi, con privilegi di root (*sudo*)

```
/sdream.sh revome 04
```



**rename** comando che rinomina la voce di menu riferita ad un gioco specifico della lista, ad esempio se volessimo modificare la voce di elenco 04 Street Fighter III - 3rd Strike in modo differente dovremmo utilizzare:

```
./sdream.sh rename 04 "Street Fighter 3 - 3rd strike"
```



**reorder** questo comando riallinea riordina la numerazione delle cartelle contenenti ii file di gioco/rom dal numero indicato

```
./sdream.sh reorder 05
```

* questo comando esegue il rigeneraione del menu di GD-Menu verrà richiesta quindi password di root (*root*)



**numbered** questo comando converte le cartelle presenti sulla scheda SD in formato numerico, non dovrebbe essere necessario salvo aver creato in precedenza cartelle con nomi non supportati da GDEMU.



**menu** questo comando rigenera il *menu* per la gestione dei giochi all'interno della scheda SD utile a GD-Menu per la gestione dei giochi/trom dal Dreamcast. Questo comando necessitá dei privilegi di root (*sudo*).

Ho realizzato questo script a livello amatoriale, non sono uno sviluppatore e non posso garantire per potenziali danni o perdite di file/informazioni per l'uso di questo script, ho realizzato questo software su Linux Mint e ho testato il funzionamento corretto per quanto possibile sui sistemi Ubutnu, Debian, Mint e Pop-OS

Spero possiate divertirvi e nello stesso tempo trovare utile questo mio piccolo contributo, fate di queste righe di ¨codice"quello che volete, sarei felice di poterlo vedere girare anche su altre distribuzioni. Qualsiasi miglioramento é ben accetto, ricordatevi peró del mio contributo iniziale. 

con amore 

#### B3LZ3BU

