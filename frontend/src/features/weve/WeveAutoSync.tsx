import React, { useState, useEffect } from 'react';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import {
  RefreshCw,
  Loader2,
  Clock,
  CheckCircle,
  AlertCircle,
} from 'lucide-react';
import api from '@/api/axios';

interface SyncStatus {
  lastSyncTime: string | null;
  isSyncing: boolean;
  isLoggedIn: boolean;
}

interface SyncResult {
  productsAdded: number;
  productsUpdated: number;
  productsSkipped?: number;
  errors?: string[];
}

export const WeveAutoSync: React.FC = () => {
  const { toast } = useToast();
  const [syncing, setSyncing] = useState(false);
  const [status, setStatus] = useState<SyncStatus>({
    lastSyncTime: null,
    isSyncing: false,
    isLoggedIn: false,
  });
  const [lastResult, setLastResult] = useState<SyncResult | null>(null);

  useEffect(() => {
    fetchSyncStatus();
    // Refresh status every 30 seconds
    const interval = setInterval(fetchSyncStatus, 30000);
    return () => clearInterval(interval);
  }, []);

  const fetchSyncStatus = async () => {
    try {
      const response = await api.get('/weve/sync/status');
      if (response.data.status === 'success') {
        setStatus(response.data.data);
      }
    } catch (error) {
      console.error('Failed to fetch sync status:', error);
    }
  };

  const triggerSync = async () => {
    if (!status.isLoggedIn) {
      toast({
        variant: 'destructive',
        title: 'Анхааруулга',
        description: 'Эхлээд Weve сайтад нэвтэрнэ үү',
      });
      return;
    }

    setSyncing(true);
    try {
      const response = await api.post('/weve/sync/trigger');

      if (response.data.status === 'success') {
        const result = response.data.data;
        setLastResult(result);

        toast({
          title: 'Sync амжилттай',
          description: `${result.productsAdded} шинэ бараа, ${result.productsUpdated} шинэчлэгдсэн`,
        });

        // Refresh status
        await fetchSyncStatus();
      } else {
        toast({
          variant: 'destructive',
          title: 'Sync амжилтгүй',
          description: response.data.message || 'Алдаа гарлаа',
        });
      }
    } catch (error: any) {
      toast({
        variant: 'destructive',
        title: 'Алдаа',
        description:
          error.response?.data?.message ||
          'Барааны мэдээлэл татахад алдаа гарлаа',
      });
    } finally {
      setSyncing(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Автомат барааны мэдээлэл sync</CardTitle>
        <CardDescription>
          Weve сайтаас барааны мэдээлэл автоматаар татаж, агуулга3-д шинэчлэх
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Status */}
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            {status.isLoggedIn ? (
              <CheckCircle className="h-4 w-4 text-green-600" />
            ) : (
              <AlertCircle className="h-4 w-4 text-yellow-600" />
            )}
            <span className="text-sm">
              {status.isLoggedIn ? 'Weve-д нэвтэрсэн' : 'Weve-д нэвтрээгүй'}
            </span>
          </div>

          {status.lastSyncTime && (
            <div className="flex items-center gap-2 text-sm text-gray-600">
              <Clock className="h-4 w-4" />
              <span>
                Сүүлд sync хийсэн:{' '}
                {new Date(status.lastSyncTime).toLocaleString('mn-MN')}
              </span>
            </div>
          )}

          {status.isSyncing && (
            <div className="flex items-center gap-2 text-sm text-blue-600">
              <Loader2 className="h-4 w-4 animate-spin" />
              <span>Одоо sync хийж байна...</span>
            </div>
          )}
        </div>

        {/* Last Result */}
        {lastResult && (
          <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg space-y-1">
            <div className="font-medium text-blue-900">
              Сүүлийн sync үр дүн:
            </div>
            <div className="text-sm text-blue-700">
              ✅ Шинэ бараа: {lastResult.productsAdded}
            </div>
            <div className="text-sm text-blue-700">
              🔄 Шинэчлэгдсэн: {lastResult.productsUpdated}
            </div>
            {lastResult.errors && lastResult.errors.length > 0 && (
              <div className="text-sm text-red-700">
                ❌ Алдаа: {lastResult.errors.length}
              </div>
            )}
          </div>
        )}

        {/* Sync Button */}
        <Button
          onClick={triggerSync}
          disabled={syncing || status.isSyncing || !status.isLoggedIn}
          className="w-full"
        >
          {syncing || status.isSyncing ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              Sync хийж байна...
            </>
          ) : (
            <>
              <RefreshCw className="mr-2 h-4 w-4" />
              Одоо sync хийх
            </>
          )}
        </Button>

        {/* Info */}
        <div className="text-xs text-gray-500 space-y-1">
          <p>
            ℹ️ Sync хийхэд Weve сайтаас бүх идэвхтэй барааны мэдээллийг татаж авна
          </p>
          <p>
            ℹ️ Бараа code эсвэл barcode-оор таарвал шинэчлэгдэнэ, үгүй бол шинээр
            нэмэгдэнэ
          </p>
          <p>
            ℹ️ Үнэ, үлдэгдэл, нэр зэрэг мэдээлэл автоматаар шинэчлэгдэнэ
          </p>
        </div>

        {/* Errors */}
        {lastResult?.errors && lastResult.errors.length > 0 && (
          <div className="p-3 bg-red-50 border border-red-200 rounded-lg">
            <div className="font-medium text-red-900 text-sm mb-2">
              Алдаанууд:
            </div>
            <div className="space-y-1 max-h-40 overflow-y-auto">
              {lastResult.errors.map((error, index) => (
                <div key={index} className="text-xs text-red-700">
                  • {error}
                </div>
              ))}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
