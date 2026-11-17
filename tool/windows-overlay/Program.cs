using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Windows.Forms;

namespace EhtidOverlay;

/// <summary>
/// Always-on-top floating controller for the existing permitted offline-memory
/// helper. No injection, hooks, global keyboard logging or target window hacks.
/// Users operate it only while a game is windowed/borderless.
/// </summary>
internal static class Program
{
    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new OverlayForm());
    }
}

internal sealed class OverlayForm : Form
{
    private const string HelperName = "EHTID-MemoryHelper.exe";
    private const int DefaultBudget = 512;
    private static readonly Color Dark = Color.FromArgb(24, 19, 37);
    private static readonly Color Panel = Color.FromArgb(38, 31, 56);
    private static readonly Color Lilac = Color.FromArgb(183, 138, 255);
    private static readonly Color Cyan = Color.FromArgb(94, 233, 245);
    private static readonly Color Muted = Color.FromArgb(204, 196, 220);

    private readonly ComboBox _games = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox _type = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly TextBox _value = new();
    private readonly TextBox _replacement = new();
    private readonly NumericUpDown _budget = new() {
        Minimum = 128, Maximum = 2048, Increment = 128, Value = DefaultBudget };
    private readonly ListBox _addresses = new();
    private readonly Label _status = new() { Text = "Выбери свою одиночную игру.", AutoSize = false };
    private readonly Button _refresh = ActionButton("Найти игры");
    private readonly Button _scan = ActionButton("Первый поиск");
    private readonly Button _refine = ActionButton("Уточнить");
    private readonly Button _write = ActionButton("Записать адрес");
    private readonly Button _restore = ActionButton("Откат");
    private readonly Button _topmost = ActionButton("Поверх всех: ВКЛ");
    private readonly Button _collapse = ActionButton("Свернуть");
    private CancellationTokenSource? _operation;
    private List<string> _hits = new();
    private string? _expected;
    private UndoRecord? _undo;
    private bool _busy;

    public OverlayForm()
    {
        Text = "EHTID · плавающий редактор";
        ClientSize = new Size(370, 620);
        MinimumSize = new Size(355, 420);
        MaximumSize = new Size(650, 900);
        FormBorderStyle = FormBorderStyle.SizableToolWindow;
        StartPosition = FormStartPosition.Manual;
        Location = new Point(Math.Max(0, Screen.PrimaryScreen!.WorkingArea.Right - 420), 80);
        TopMost = true;
        BackColor = Dark;
        ForeColor = Color.White;
        Font = new Font("Segoe UI", 9F);
        ShowInTaskbar = true;
        KeyPreview = true;

        var body = new TableLayoutPanel {
            Dock = DockStyle.Fill,
            Padding = new Padding(12),
            ColumnCount = 1,
            RowCount = 11,
            BackColor = Dark
        };
        for (int i = 0; i < 11; i++)
            body.RowStyles.Add(new RowStyle(SizeType.Absolute, i switch {
                0 => 34, 1 => 31, 2 => 49, 3 => 49,
                4 => 47, 5 => 47, 6 => 36, 7 => 32,
                8 => 38, 9 => 180, _ => 72
            }));
        Controls.Add(body);

        var header = new Label {
            Text = "◈  EHTID   /   LIVE MEMORY", Dock = DockStyle.Fill,
            Font = new Font("Segoe UI", 12F, FontStyle.Bold),
            ForeColor = Cyan, TextAlign = ContentAlignment.MiddleLeft,
        };
        body.Controls.Add(header, 0, 0);
        var shortNote = SmallLabel("Офлайн-игры · интерактивная панель поверх окна");
        body.Controls.Add(shortNote, 0, 1);

        var processRow = Row();
        _games.Width = 260;
        _games.BackColor = Panel; _games.ForeColor = Color.White;
        _games.FlatStyle = FlatStyle.Popup;
        _games.SelectedIndexChanged += (_, _) => ClearSearch();
        _games.DropDownWidth = 340;
        _refresh.Width = 75;
        _refresh.Click += async (_, _) => await LoadGames();
        processRow.Controls.Add(_games);
        processRow.Controls.Add(_refresh);
        body.Controls.Add(processRow, 0, 2);

        var inputRow = Row();
        _value.Width = 205; _value.PlaceholderText = "HP / мана / деньги";
        _value.BackColor = Panel; _value.ForeColor = Color.White;
        _type.Width = 129; _type.BackColor = Panel; _type.ForeColor = Color.White;
        _type.Items.AddRange(new object[] {
            new FormatItem("i32", "Int32"), new FormatItem("i64", "Int64"),
            new FormatItem("f32", "Float32"), new FormatItem("f64", "Float64")
        });
        _type.SelectedIndex = 0;
        _type.SelectedIndexChanged += (_, _) => ClearSearch();
        inputRow.Controls.Add(_value); inputRow.Controls.Add(_type);
        body.Controls.Add(inputRow, 0, 3);

        var searchRow = Row();
        _scan.Width = 165; _refine.Width = 165;
        _scan.Click += async (_, _) => await Search(false);
        _refine.Click += async (_, _) => await Search(true);
        searchRow.Controls.Add(_scan); searchRow.Controls.Add(_refine);
        body.Controls.Add(searchRow, 0, 4);

        var limitRow = Row();
        limitRow.Controls.Add(SmallLabel("Сканировать до (МиБ)"));
        _budget.Width = 107;
        limitRow.Controls.Add(_budget);
        body.Controls.Add(limitRow, 0, 5);

        body.Controls.Add(SmallLabel("КАНДИДАТЫ / выбери адрес для точечной записи"), 0, 6);

        var changeRow = Row();
        _replacement.Width = 205; _replacement.PlaceholderText = "Новое значение";
        _replacement.BackColor = Panel; _replacement.ForeColor = Color.White;
        _write.Width = 129;
        _write.Click += async (_, _) => await WriteSelected();
        changeRow.Controls.Add(_replacement);
        changeRow.Controls.Add(_write);
        body.Controls.Add(changeRow, 0, 7);

        var actions = Row();
        _restore.Width = 80; _topmost.Width = 150; _collapse.Width = 100;
        _restore.Click += async (_, _) => await Undo();
        _topmost.Click += (_, _) => {
            TopMost = !TopMost;
            _topmost.Text = TopMost ? "Поверх всех: ВКЛ" : "Поверх всех: ВЫКЛ";
        };
        _collapse.Click += (_, _) => WindowState = FormWindowState.Minimized;
        actions.Controls.Add(_restore); actions.Controls.Add(_topmost); actions.Controls.Add(_collapse);
        body.Controls.Add(actions, 0, 8);

        _addresses.Dock = DockStyle.Fill;
        _addresses.BackColor = Panel; _addresses.ForeColor = Cyan;
        _addresses.BorderStyle = BorderStyle.FixedSingle;
        _addresses.Font = new Font("Consolas", 10F);
        body.Controls.Add(_addresses, 0, 9);
        _status.Dock = DockStyle.Fill; _status.ForeColor = Muted;
        _status.Padding = new Padding(2, 6, 2, 0);
        body.Controls.Add(_status, 0, 10);

        _refine.Enabled = false;
        _write.Enabled = false;
        _restore.Enabled = false;
        _addresses.SelectedIndexChanged += (_, _) => UpdateButtons();
        Resize += (_, _) => {
            // Keep visible controls usable across common game resolutions.
            _addresses.Height = Math.Max(100, ClientSize.Height - 420);
        };
        Shown += async (_, _) => await LoadGames();
    }

    private static FlowLayoutPanel Row() => new() {
        Dock = DockStyle.Fill, WrapContents = false, AutoScroll = false,
        Margin = new Padding(0, 3, 0, 0), BackColor = Dark
    };

    private static Label SmallLabel(string value) => new() {
        Text = value, ForeColor = Muted, AutoSize = true,
        TextAlign = ContentAlignment.MiddleLeft, Margin = new Padding(4, 8, 8, 0)
    };

    private static Button ActionButton(string name) => new() {
        Text = name, Height = 29, FlatStyle = FlatStyle.Flat,
        BackColor = Panel, ForeColor = Color.White,
        Margin = new Padding(2, 0, 2, 0), Cursor = Cursors.Hand
    };

    private int? Pid => (_games.SelectedItem as GameItem)?.Pid;
    private string Format => (_type.SelectedItem as FormatItem)?.Code ?? "i32";

    private void ClearSearch()
    {
        _hits.Clear();
        _addresses.Items.Clear();
        _expected = null;
        _undo = null;
        UpdateButtons();
    }

    private void UpdateButtons()
    {
        _refresh.Enabled = !_busy; _scan.Enabled = !_busy;
        _refine.Enabled = !_busy && _hits.Count > 0;
        _write.Enabled = !_busy && _expected != null && _addresses.SelectedIndex >= 0;
        _restore.Enabled = !_busy && _undo != null;
        _type.Enabled = !_busy; _games.Enabled = !_busy;
        _budget.Enabled = !_busy;
    }

    private async Task<JsonElement> Request(object body)
    {
        string helper = Path.Combine(AppContext.BaseDirectory, HelperName);
        if (!File.Exists(helper))
            throw new FileNotFoundException("Рядом с оверлеем нет EHTID-MemoryHelper.exe");
        using var process = new Process();
        process.StartInfo = new ProcessStartInfo(helper) {
            UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true,
            RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8,
        };
        if (!process.Start()) throw new IOException("Не удалось запустить модуль памяти");
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(120));
        _operation = timeout;
        var outputTask = process.StandardOutput.ReadToEndAsync();
        var errorTask = process.StandardError.ReadToEndAsync();
        await process.StandardInput.WriteAsync(JsonSerializer.Serialize(body));
        process.StandardInput.Close();
        try { await process.WaitForExitAsync(timeout.Token); }
        catch (OperationCanceledException) {
            if (!process.HasExited) process.Kill(entireProcessTree: true);
            throw new TimeoutException("Сканирование превысило 120 секунд");
        }
        finally { _operation = null; }
        var output = await outputTask;
        var error = await errorTask;
        if (string.IsNullOrWhiteSpace(output))
            throw new IOException($"Нет ответа от сканера: {error}");
        using var doc = JsonDocument.Parse(output);
        var root = doc.RootElement.Clone();
        if (!root.TryGetProperty("ok", out var ok) || !ok.GetBoolean())
            throw new InvalidOperationException(root.TryGetProperty("error", out var err)
                ? err.GetString() ?? "Операция не выполнена" : "Ошибка сканера");
        if (process.ExitCode != 0) throw new IOException("Модуль завершился с ошибкой");
        return root;
    }

    private async Task LoadGames()
    {
        if (_busy) return;
        SetBusy(true, "Ищу видимые окна игр…");
        try {
            var data = await Request(new { command = "list" });
            var values = data.GetProperty("processes").EnumerateArray().Select(x =>
                new GameItem(
                    x.GetProperty("pid").GetInt32(),
                    x.GetProperty("name").GetString() ?? "",
                    x.GetProperty("title").GetString() ?? "")).ToArray();
            var oldPid = Pid;
            _games.Items.Clear();
            _games.Items.AddRange(values.Cast<object>().ToArray());
            if (oldPid.HasValue) {
                for (int i = 0; i < _games.Items.Count; i++)
                    if ((_games.Items[i] as GameItem)?.Pid == oldPid.Value)
                        _games.SelectedIndex = i;
            }
            _status.Text = $"Видимых окон: {values.Length}. Выбери свою офлайн-игру.";
        }
        catch (Exception error) { _status.Text = error.Message; }
        finally { SetBusy(false); }
    }

    private static bool ValidNumber(string text, string type)
    {
        text = text.Replace(',', '.').Trim();
        switch (type)
        {
            case "i32": return int.TryParse(text, NumberStyles.Integer,
                    CultureInfo.InvariantCulture, out _);
            case "i64": return long.TryParse(text, NumberStyles.Integer,
                    CultureInfo.InvariantCulture, out _);
            case "f32": return float.TryParse(text, NumberStyles.Float,
                    CultureInfo.InvariantCulture, out var single) && float.IsFinite(single);
            case "f64": return double.TryParse(text, NumberStyles.Float,
                    CultureInfo.InvariantCulture, out var dbl) && double.IsFinite(dbl);
            default: return false;
        }
    }

    private async Task Search(bool refine)
    {
        if (_busy) return;
        if (Pid is not int pid) { _status.Text = "Выбери игру"; return; }
        var value = _value.Text.Trim().Replace(',', '.');
        if (!ValidNumber(value, Format)) { _status.Text = "Введи допустимое число"; return; }
        if (refine && _hits.Count == 0) return;
        var previous = _hits.ToArray();
        SetBusy(true, refine ? "Уточняю совпадения…" : "Сканирую разрешённую память…");
        try
        {
            object payload = refine
                ? new { command = "refine", pid, format = Format, value, addresses = previous }
                : new { command = "scan", pid, format = Format, value,
                    maxBytes = (long)_budget.Value * 1024 * 1024, maxResults = 3000,
                    alignment = Format.EndsWith("64") ? 8 : 4 };
            var result = await Request(payload);
            _hits = result.GetProperty("addresses").EnumerateArray()
                .Select(x => x.GetString() ?? "").ToList();
            _addresses.Items.Clear();
            _addresses.Items.AddRange(_hits.Cast<object>().ToArray());
            _expected = value;
            _undo = null;
            var cap = result.TryGetProperty("truncated", out var truncated) &&
                truncated.GetBoolean();
            _status.Text = $"Найдено: {_hits.Count}. " +
                (cap ? "Лимит совпадений; уточни значение. " : "") +
                "Измени показатель в игре и нажми «Уточнить».";
        }
        catch (Exception error) { _status.Text = error.Message; }
        finally { SetBusy(false); }
    }

    private async Task WriteSelected()
    {
        if (_busy || Pid is not int pid || _addresses.SelectedItem is not string address ||
            _expected == null) return;
        var replacement = _replacement.Text.Trim().Replace(',', '.');
        if (!ValidNumber(replacement, Format)) {
            _status.Text = "Неверный формат нового значения"; return;
        }
        string format = Format;
        string expected = _expected;
        if (MessageBox.Show(this,
            $"Изменить ТОЛЬКО адрес {address} процесса PID {pid}?\n" +
            $"{expected} → {replacement}\n\n" +
            "Подтверждаешь, что это твоя одиночная игра? Ошибочная запись может вызвать вылет.",
            "EHTID · подтверждение RAM-записи", MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
            return;

        SetBusy(true, "Проверяю исходные байты и записываю одно значение…");
        try {
            await Request(new { command = "write", pid, format, address,
                expected, replacement });
            _undo = new UndoRecord(pid, format, address, expected, replacement);
            _expected = replacement;
            _value.Text = replacement;
            _hits = new List<string> { address };
            _addresses.Items.Clear(); _addresses.Items.Add(address);
            _addresses.SelectedIndex = 0;
            _status.Text = $"Записано и проверено: {address} · {expected} → {replacement}";
        }
        catch (Exception error) { _status.Text = "Запись отклонена: " + error.Message; }
        finally { SetBusy(false); }
    }

    private async Task Undo()
    {
        var restore = _undo;
        if (_busy || restore == null) return;
        SetBusy(true, "Восстанавливаю последнее значение…");
        try {
            await Request(new {
                command = "write", pid = restore.Pid,
                format = restore.Format, address = restore.Address,
                expected = restore.After, replacement = restore.Before
            });
            _expected = restore.Before; _value.Text = restore.Before;
            _undo = null;
            _status.Text = "Прежнее значение восстановлено и проверено.";
        }
        catch (Exception error) { _status.Text = "Откат отклонён: " + error.Message; }
        finally { SetBusy(false); }
    }

    private void SetBusy(bool busy, string? status = null)
    {
        _busy = busy;
        if (status != null) _status.Text = status;
        UpdateButtons();
    }

    private sealed record GameItem(int Pid, string Name, string WindowTitle)
    {
        public override string ToString() => $"{Name} · {WindowTitle} (PID {Pid})";
    }

    private sealed record FormatItem(string Code, string Label)
    {
        public override string ToString() => Label;
    }

    private sealed record UndoRecord(int Pid, string Format, string Address,
        string Before, string After);
}
