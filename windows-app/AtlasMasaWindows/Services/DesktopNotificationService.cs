using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;

namespace AtlasMasaWindows.Services;

public sealed class DesktopNotificationService
{
    private bool _isRegistered;

    public bool IsAvailable => AppNotificationManager.IsSupported();

    public void EnsureRegistered()
    {
        if (_isRegistered || !IsAvailable)
        {
            return;
        }

        try
        {
            AppNotificationManager.Default.Register();
            _isRegistered = true;
        }
        catch
        {
            _isRegistered = false;
        }
    }

    public void Show(string title, string body)
    {
        if (!IsAvailable)
        {
            return;
        }

        EnsureRegistered();
        if (!_isRegistered)
        {
            return;
        }

        try
        {
            var builder = new AppNotificationBuilder()
                .AddText(title)
                .AddText(body);
            var payload = builder.BuildNotification();
            var notification = new AppNotification(payload);
            AppNotificationManager.Default.Show(notification);
        }
        catch
        {
            // Best effort only.
        }
    }
}
