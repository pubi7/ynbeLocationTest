# Aguulga Business App

A Flutter mobile application for business management with GPS tracking, sales, and order management.

## Features

### For Boss/Manager:
- View GPS information of company vehicles
- Dashboard with sales and order overviews
- Vehicle tracking with real-time location

### For Sales Staff:
- **Sales**: Record product sales with location and amount
- **Take Order**: Create orders similar to Nomin's ordering system
- **View Shop/Store**: View all shops with locations and route optimization

## Demo Credentials

### Boss/Manager:
- Email: `boss@company.com`
- Password: `boss123`

### Sales Staff:
- Email: `sales@company.com`
- Password: `sales123`

## Setup Instructions

1. **Install Flutter** (if not already installed):
   ```bash
   # Check if Flutter is installed
   flutter --version
   ```

2. **Get Dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run the App**:
   ```bash
   # For Android
   flutter run

   # For iOS (if on macOS)
   flutter run -d ios
   ```

## Important Notes

- **Google Maps API Key**: You need to add your Google Maps API key in `android/app/src/main/AndroidManifest.xml` (replace `YOUR_GOOGLE_MAPS_API_KEY_HERE`)
- **Location Permissions**: The app requests location permissions for GPS tracking
- **Mock Data**: All data is currently mock data - no backend required

## App Structure

- **Authentication**: Login/Register with role-based access
- **Boss Dashboard**: Vehicle tracking and business overview
- **Sales Dashboard**: Sales entry, order taking, and shop viewing
- **GPS Tracking**: Real-time vehicle location tracking
- **Route Optimization**: Shows fastest routes to shops (UI ready)

## Screens

1. **Login/Register** - Role-based authentication
2. **Boss Dashboard** - Business overview and vehicle tracking
3. **Sales Dashboard** - Sales staff main menu
4. **Sales Entry** - Record new sales
5. **Order Screen** - Take orders from customers
6. **Shop View** - View shops with map and route optimization
7. **Vehicle Tracking** - GPS tracking for company vehicles

The app is ready to run with mock data and doesn't require any database setup!
