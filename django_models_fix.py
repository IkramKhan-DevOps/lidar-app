# UPDATED DJANGO MODELS - Copy this to your Django project

from django.db import models
from src.core.bll import get_action_urls
from src.services.users.models import User

class Scan(models.Model):
    """
    Represents a 3D scan session initiated by a technician in the field.
    Stores metadata like duration, area, height, and file size of the scan.
    """

    allowed_actions = ["detail"]

    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='scans',
        help_text="User (technician) who performed the scan."
    )
    scan_id = models.PositiveIntegerField(unique=True, null=True, blank=False)
    title = models.CharField(max_length=255, help_text="Descriptive title for the scan session.")
    description = models.TextField(blank=True, help_text="Optional notes about the scan.")
    duration = models.IntegerField(help_text="Duration of the scan in seconds.")
    area_covered = models.FloatField(help_text="Area covered during the scan (m²).")
    height = models.FloatField(help_text="Max vertical height captured (m).")
    data_size_mb = models.FloatField(help_text="Size of scan data (MB).")
    location = models.CharField(max_length=250)

    created_at = models.DateTimeField(auto_now_add=True, help_text="Record creation timestamp.")
    updated_at = models.DateTimeField(auto_now=True, help_text="Record last updated timestamp.")

    def __str__(self):
        return f"{self.title} - {self.user.username}"

    @property
    def get_display_fields(self):
        """Return fields that should be displayed in the template."""
        return [
            'title', 'duration', 'area_covered', 'data_size_mb', 'created_at'
        ]

    def get_action_urls(self, user):
        return get_action_urls(self, user)


class GPSPath(models.Model):
    """
    Stores a single GPS coordinate from a scan session.
    """

    scan = models.ForeignKey(
        Scan,
        on_delete=models.CASCADE,
        related_name='gps_points',
        help_text="Scan session associated with this GPS point."
    )
    # FIXED: Changed from CharField to FloatField for proper numeric handling
    latitude = models.FloatField(help_text="Latitude (decimal degrees).")
    longitude = models.FloatField(help_text="Longitude (decimal degrees).")

    accuracy = models.FloatField(help_text="GPS accuracy (m).", default=100)
    timestamp = models.DateTimeField(auto_now_add=True, help_text="Time this GPS point was recorded.")

    def __str__(self):
        return f"{self.latitude}, {self.longitude} ({self.scan.title})"


# Updated Serializer with proper type handling
class GPSPathSerializer(serializers.ModelSerializer):
    class Meta:
        model = GPSPath
        fields = ['id', 'latitude', 'longitude', 'accuracy', 'timestamp']


class ScanPointCloudSerializer(serializers.ModelSerializer):
    class Meta:
        model = ScanPointCloud
        fields = ['id', 'gray_model', 'processed_model', 'point_count', 'snapshot', 'uploaded_at']


class UploadStatusSerializer(serializers.ModelSerializer):
    class Meta:
        model = UploadStatus
        fields = ['id', 'status', 'last_attempt', 'retry_count', 'error_message']


class ScanImageSerializer(serializers.ModelSerializer):
    class Meta:
        model = ScanImage
        fields = ['id', 'image', 'caption', 'timestamp']


class ScanDetailSerializer(serializers.ModelSerializer):
    user = serializers.PrimaryKeyRelatedField(queryset=User.objects.all())
    gps_points = GPSPathSerializer(many=True, read_only=True)
    point_cloud = ScanPointCloudSerializer(read_only=True)
    upload_status = UploadStatusSerializer(read_only=True)
    images = ScanImageSerializer(many=True, read_only=True)
    total_images = serializers.SerializerMethodField()
    status = serializers.SerializerMethodField()

    class Meta:
        model = Scan
        fields = [
            'id', 'user', 'title', 'description',
            'duration', 'area_covered', 'height', 'data_size_mb',
            'status',
            'gps_points', 'point_cloud', 'upload_status', 'images',
            'total_images',
            'created_at', 'updated_at',
        ]

    def get_total_images(self, obj):
        return obj.images.count()

    def get_status(self, obj):
        return obj.upload_status.status if hasattr(obj, 'upload_status') and obj.upload_status else None

    def to_representation(self, instance):
        """
        Ensure consistent data types in API response
        """
        data = super().to_representation(instance)
        
        # Ensure numeric fields are properly typed
        data['duration'] = int(data['duration']) if data.get('duration') else 0
        data['area_covered'] = float(data['area_covered']) if data.get('area_covered') else 0.0
        data['height'] = float(data['height']) if data.get('height') else 0.0
        data['data_size_mb'] = float(data['data_size_mb']) if data.get('data_size_mb') else 0.0
        data['total_images'] = int(data['total_images']) if data.get('total_images') else 0
        
        return data
