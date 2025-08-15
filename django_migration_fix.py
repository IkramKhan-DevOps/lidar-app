# Django migration to fix GPS coordinate field types
# Run this in your Django project:

# 1. First, generate the migration:
# python manage.py makemigrations --name fix_gps_coordinates

# 2. This will create a migration file similar to:

from django.db import migrations, models

class Migration(migrations.Migration):

    dependencies = [
        ('your_app_name', '0001_initial'),  # Replace with your actual last migration
    ]

    operations = [
        # Convert GPS coordinates from CharField to FloatField
        migrations.AlterField(
            model_name='gpspath',
            name='latitude',
            field=models.FloatField(help_text='Latitude (decimal degrees).'),
        ),
        migrations.AlterField(
            model_name='gpspath',
            name='longitude',
            field=models.FloatField(help_text='Longitude (decimal degrees).'),
        ),
    ]

# 3. Run the migration:
# python manage.py migrate

# NOTE: If you have existing string data in latitude/longitude fields,
# you might need a data migration to convert them:

# Create a data migration:
# python manage.py makemigrations --empty your_app_name --name convert_gps_strings_to_floats

# Then edit the migration file to add:

def convert_gps_strings_to_floats(apps, schema_editor):
    GPSPath = apps.get_model('your_app_name', 'GPSPath')
    for gps_point in GPSPath.objects.all():
        try:
            # Convert string coordinates to float
            if isinstance(gps_point.latitude, str):
                gps_point.latitude = float(gps_point.latitude)
            if isinstance(gps_point.longitude, str):
                gps_point.longitude = float(gps_point.longitude)
            gps_point.save()
        except (ValueError, TypeError):
            # Handle invalid coordinate data
            print(f"Warning: Could not convert GPS coordinates for point {gps_point.id}")

def reverse_conversion(apps, schema_editor):
    # Reverse operation if needed
    pass

class Migration(migrations.Migration):
    operations = [
        migrations.RunPython(convert_gps_strings_to_floats, reverse_conversion),
    ]
