# Social Ride App — Design Spec

Data: 2026-11-18

## Obiettivo

App mobile per gruppi di social ride (ciclismo) con due funzioni:
1. Posizione live condivisa tra i partecipanti alla ride.
2. Comunicazione rapida tra i rider: alert automatico quando qualcuno si
   stacca dal gruppo, e messaggi vocali brevi per coordinarsi.

Motivazione: unire in un'unica app, con UX pensata per questo caso
d'uso specifico, funzioni che oggi sono sparse tra più app (Strava
Beacon, Zello, WhatsApp). Obiettivo secondario: progetto per imparare
sviluppo mobile.

## Vincoli e contesto

- Target: gruppo piccolo, 5-15 persone per ride.
- Piattaforme: Android e iOS dal primo rilascio.
- Utente non può interagire con il telefono mentre pedala: qualunque
  segnalazione di distacco deve essere automatica, non richiedere
  azione manuale.
- Sviluppatore conosce solo Java, nessuna esperienza con Python/C/C#,
  0 codice scritto negli ultimi 3 anni. Vuole scrivere il codice in
  prima persona, con guida e review.
- Budget: nullo/minimo per backend e hosting.

## Stack

- **Frontend**: Flutter (Dart), codice unico per Android e iOS.
  Scelto su React Native perché Dart (OOP, tipizzazione statica,
  classi/interfacce) è sintatticamente più vicino a Java.
- **Backend**: Firebase, nessun server custom.
  - Firestore: dati ride, posizioni, messaggi (realtime).
  - Cloud Functions: logica di rilevamento distacco, trigger notifiche.
  - Cloud Messaging: push notifications.
  - Storage: file audio dei messaggi vocali.
  - Free tier sufficiente per il volume previsto (gruppo 5-15, poche
    ride a settimana).

## Modello dati (Firestore)

```
rides/{rideId}
  name: string
  creatorId: string
  status: "active" | "closed"
  createdAt: timestamp
  dropoffThresholdMeters: number (default 300)

rides/{rideId}/riders/{userId}
  displayName: string
  lastPosition: { lat, lng, timestamp }
  state: "in_group" | "dropped_off"

rides/{rideId}/messages/{messageId}
  senderId: string
  audioUrl: string
  durationSeconds: number
  createdAt: timestamp
```

Le ride sono temporanee: dati conservati per lo storico/debug con TTL
(es. 24h), poi eliminati automaticamente.

## Flusso ride

1. Un rider crea una ride → l'app genera un codice/link condivisibile.
2. Gli altri rider entrano inserendo il codice o aprendo il link →
   diventano documenti in `riders`.
3. Durante la ride, ogni client scrive la propria posizione in
   Firestore ogni ~10 secondi.
4. La mappa (Google Maps Flutter plugin) mostra la posizione di tutti
   i rider in tempo reale.
5. Il creatore chiude la ride a fine giro; i dati scadono dopo il TTL.

## Rilevamento automatico distacco

Cloud Function innescata a ogni scrittura di posizione:

1. Calcola la distanza del rider dal centroide del gruppo (o dal
   rider più vicino).
2. Se la distanza supera `dropoffThresholdMeters` per più di una
   finestra minima (es. 60 secondi consecutivi, per filtrare falsi
   positivi come un semaforo), lo stato del rider passa a
   `dropped_off`.
3. Al cambio di stato, push notification a tutti gli altri rider:
   "<nome> si è staccato (~<distanza>m)".
4. Quando il rider rientra sotto soglia, lo stato torna a
   `in_group` (notifica di rientro opzionale, non bloccante per v1).

## Messaggi vocali

- Bottone di registrazione in app, durata massima 15-20 secondi.
- Al termine: upload su Firebase Storage, scrittura documento in
  `messages`, push notification a tutto il gruppo.
- In app: lista cronologica dei messaggi della ride, riproducibili;
  autoplay opzionale per il messaggio appena arrivato.
- Non è audio in tempo reale (niente streaming/WebRTC): scelta per
  mantenere la complessità bassa e compatibile con l'uso in bici
  (il mittente registra fermo o a bordo strada, non in movimento).

## Gestione errori

- Permesso posizione negato o GPS assente: schermata di blocco con
  spiegazione, nessun crash silenzioso.
- Perdita di connettività durante la ride: le posizioni vengono
  accodate localmente e sincronizzate al ritorno della rete.
- Batteria: intervallo di aggiornamento posizione configurabile;
  avviso quando la batteria scende sotto il 20%.

## Testing

- Unit test sulla logica di distanza/soglia per il rilevamento
  distacco (puro Dart, nessuna dipendenza da GPS reale).
- Test manuale su strada per i comportamenti che dipendono da GPS,
  permessi di background e batteria: non automatizzabile in modo
  affidabile, va verificato con ride reali.

## Fuori scope per v1

- Audio in tempo reale stile walkie-talkie vero (streaming/WebRTC).
- Gruppi/ride persistenti (ogni ride è creata ed esaurita singolarmente).
- Supporto a gruppi grandi (50+ persone) o scalabilità oltre il caso
  d'uso di un ride club.
