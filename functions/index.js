/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {onRequest} = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
// const functions = require('firebase-functions');
const functions = require("firebase-functions/v1");
const admin = require('firebase-admin');
admin.initializeApp();

// Función para enviar notificación cuando la humedad supere el 60%
exports.sendHumidityNotification = functions.database.ref('/sensors/humidity')
    .onUpdate((change, context) => {
        const newValue = change.after.val();
      
        // Obtén el timestamp de la última notificación desde el nodo '/sensors/lastNotificationTimestamp'
        return admin.database().ref('/sensors/lastNotificationTimestamp').once('value')
          .then(snapshot => {
            const lastNotificationTimestamp = snapshot.val() || 0;
            const currentTimestamp = Date.now();
  
            // Si la humedad supera el umbral (60%) y han pasado más de 12 horas desde la última notificación
            if (newValue > 60 && currentTimestamp - lastNotificationTimestamp > 12 * 60 * 60 * 1000) {
              const message = {
                notification: {
                  title: '¡Alerta de Humedad!',
                  body: 'La humedad ha superado el 60%. ¡Toma acción!'
                },
                topic: 'humidityAlert', // Enviar la notificación al topic
              };
  
              // Envía la notificación a todos los dispositivos suscritos al tópico
              return admin.messaging().send(message)
                .then((response) => {
                  console.log('Notificación enviada con éxito:', response);
                  // Actualizar el timestamp de la última notificación en la base de datos
                  return admin.database().ref('/sensors').update({
                    lastNotificationTimestamp: currentTimestamp
                  });
                })
                .catch((error) => {
                  console.error('Error al enviar notificación:', error);
                  return null;
                });
            }
            return null;
          });
      });
// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
