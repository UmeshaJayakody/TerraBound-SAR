# TripTap – Vehicle Renting Platform

TripTap is a full-featured online vehicle renting marketplace built using Node.js and MongoDB, with a React.js frontend. It allows vehicle owners to list their vehicles for rent and users to search, book, and pay for rentals securely. Integrated with Google Maps API for advanced location-based features.

---

## Tech Stack

- **Backend:** Node.js (Express.js)  
- **Frontend:** React.js (with Tailwind CSS for styling)  
- **Database:** MongoDB (NoSQL)  
- **Authentication:** JSON Web Tokens (JWT) with bcrypt  
- **Payment Gateway:** (Not yet implemented)  
- **Location Services:** Google Maps API  
- **Email Notifications:** Nodemailer + SMTP  
- **Deployment:** (Optional) Docker, AWS/Heroku/Vercel  

---

## Features

### Service Provider Profiles
- Register and create vehicle listings.  
- Set pricing, availability, photos, and rental terms.  
- Manage bookings and reviews.  

### Vehicle Listings & Search
- Browse or search vehicles by:  
  - Type (car, bike, van)  
  - Location (via Google Maps)  
  - Price range and availability  
- View vehicle profiles and owner details.  

### Booking Management
- Book vehicles with start/end dates.  
- View, cancel, or modify bookings.  
- Real-time availability tracking.  

### Secure Payment Processing
- Integrate with Stripe/PayPal for safe transactions.  
- Link payment with booking status.  

### Messaging System
- Communication between users and providers.  
- Share pickup instructions, availability, and feedback.  

### Review and Rating System
- Users can rate and review vehicle providers.  
- Optional: Allow providers to review users.  

### Email Notifications
- Booking confirmations and reminders.  
- Cancellations and rescheduling alerts.  
- Notifications for reviews and messages.  

### Admin Dashboard
- Manage users, listings, and transactions.  
- Moderate reviews and vehicle approvals.  
- View booking and revenue statistics.  

---

## Google Maps Integration

TripTap integrates Google Maps API for location-aware features:

- **Location Picker:** Set exact vehicle location.  
- **Search by Proximity:** Filter nearby vehicles.  
- **Map View:** Show vehicles on an interactive map.  
- **Route Display:** Pickup and drop-off routing.  

---
