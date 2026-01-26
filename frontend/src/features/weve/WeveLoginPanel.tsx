import React, { useState, useEffect } from 'react';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useToast } from '@/hooks/use-toast';
import { LogIn, LogOut, Loader2, CheckCircle, XCircle } from 'lucide-react';
import api from '@/api/axios';

interface WeveSession {
  isLoggedIn: boolean;
  session: {
    userId: number;
    userName: string;
    expiresAt: string;
    isActive: boolean;
  } | null;
}

export const WeveLoginPanel: React.FC = () => {
  const { toast } = useToast();
  const [loading, setLoading] = useState(false);
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [session, setSession] = useState<WeveSession>({
    isLoggedIn: false,
    session: null,
  });

  useEffect(() => {
    checkSessionStatus();
  }, []);

  const checkSessionStatus = async () => {
    try {
      const response = await api.get('/weve/auth/session');
      if (response.data.status === 'success') {
        setSession(response.data.data);
      }
    } catch (error) {
      console.error('Failed to check session:', error);
    }
  };

  const handleLogin = async () => {
    if (!username || !password) {
      toast({
        variant: 'destructive',
        title: 'Алдаа',
        description: 'Нэвтрэх нэр болон нууц үг оруулна уу',
      });
      return;
    }

    setLoading(true);
    try {
      const response = await api.post('/weve/auth/login', {
        username,
        password,
      });

      if (response.data.status === 'success') {
        toast({
          title: 'Амжилттай',
          description: 'Weve-д амжилттай нэвтэрлээ',
        });

        // Clear password
        setPassword('');

        // Refresh session status
        await checkSessionStatus();
      }
    } catch (error: any) {
      toast({
        variant: 'destructive',
        title: 'Нэвтрэх амжилтгүй',
        description:
          error.response?.data?.message || 'Нэвтрэх нэр эсвэл нууц үг буруу байна',
      });
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = async () => {
    setLoading(true);
    try {
      await api.post('/weve/auth/logout');

      toast({
        title: 'Амжилттай',
        description: 'Weve-ээс гарлаа',
      });

      // Clear form
      setUsername('');
      setPassword('');

      // Refresh session status
      await checkSessionStatus();
    } catch (error: any) {
      toast({
        variant: 'destructive',
        title: 'Алдаа',
        description: 'Гарахад алдаа гарлаа',
      });
    } finally {
      setLoading(false);
    }
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle>Weve Сайт Нэвтрэх</CardTitle>
        <CardDescription>
          Агуулга3-ийн нэвтрэх нэр болон нууц үгээрээ Weve сайтад нэвтрэх
        </CardDescription>
      </CardHeader>
      <CardContent>
        {session.isLoggedIn && session.session ? (
          <div className="space-y-4">
            <div className="flex items-center gap-2 p-4 bg-green-50 border border-green-200 rounded-lg">
              <CheckCircle className="h-5 w-5 text-green-600" />
              <div className="flex-1">
                <div className="font-medium text-green-900">
                  Нэвтэрсэн: {session.session.userName}
                </div>
                <div className="text-sm text-green-700">
                  Хүчинтэй хугацаа:{' '}
                  {new Date(session.session.expiresAt).toLocaleString('mn-MN')}
                </div>
              </div>
            </div>

            <Button
              onClick={handleLogout}
              disabled={loading}
              variant="outline"
              className="w-full"
            >
              {loading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <LogOut className="mr-2 h-4 w-4" />
              )}
              Гарах
            </Button>
          </div>
        ) : (
          <div className="space-y-4">
            <div className="flex items-center gap-2 p-4 bg-yellow-50 border border-yellow-200 rounded-lg">
              <XCircle className="h-5 w-5 text-yellow-600" />
              <div className="text-sm text-yellow-800">
                Weve сайтад нэвтрээгүй байна
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="weve-username">Нэвтрэх нэр</Label>
              <Input
                id="weve-username"
                type="text"
                placeholder="admin@aguulga3"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                onKeyPress={(e) => {
                  if (e.key === 'Enter') {
                    handleLogin();
                  }
                }}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="weve-password">Нууц үг</Label>
              <Input
                id="weve-password"
                type="password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                onKeyPress={(e) => {
                  if (e.key === 'Enter') {
                    handleLogin();
                  }
                }}
              />
            </div>

            <Button
              onClick={handleLogin}
              disabled={loading}
              className="w-full"
            >
              {loading ? (
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
              ) : (
                <LogIn className="mr-2 h-4 w-4" />
              )}
              Нэвтрэх
            </Button>

            <div className="text-xs text-gray-500 mt-2">
              💡 Агуулга3 системд нэвтрэх өөрийн нэвтрэх нэр болон нууц үгээ
              ашиглана уу
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
