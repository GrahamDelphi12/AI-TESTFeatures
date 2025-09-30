unit Unit1;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.StdCtrls,
  System.Net.URLClient, System.Net.HttpClient,
  System.JSON, FMX.Controls.Presentation, System.Threading, FMX.ListBox, FMX.Edit, FMX.Layouts,
  FMX.Objects, FMX.TabControl, System.NetEncoding;

type
  TForm1 = class(TForm)
    LabelTemperature: TLabel;
    LabelWindspeed: TLabel;
    Button2: TButton;
    procedure Button2Click(Sender: TObject);
  private
    FPendingTemperature: Double;
    FPendingWindSpeed: Double;
    FProgressBar: TProgressBar;
    FPendingProgress: Single;
    EditLat: TEdit;
    EditLon: TEdit;
    ComboCity: TComboBox;
    RootLayout: TLayout;
    LocationLayout: TLayout;
    ActionsLayout: TLayout;
    ReadingsLayout: TLayout;
    TitleBar: TToolBar;
    TitleLabel: TLabel;
    TabControl: TTabControl;
    TabWeather: TTabItem;
    TabGallery: TTabItem;
    GalleryScrollBox: TScrollBox;
    GalleryImages: array[0..3] of TImage;
    GalleryCaptions: array[0..3] of TLabel;
    FPendingImageIndex: Integer;
    FPendingImageData: TBytes;
    FPendingImageRequestId: Integer;
    FGalleryRequestId: Integer;
    FPendingImageCaption: string;
    procedure RefreshWeather;
    procedure UpdateLabels(const TemperatureC, WindSpeed: Double);
    procedure DoUpdateLabels;
    procedure ShowUnavailable;
    procedure ShowError;
    procedure UpdateProgress;
    procedure StartProgress;
    procedure FinishProgress;
    procedure HTTPReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var Abort: Boolean);
    procedure ComboCityChange(Sender: TObject);
    procedure ComboCityCloseUp(Sender: TObject);
    procedure LoadCityImages(const CityName: string);
    function MakeCityImageUrl(const Term: string): string;
    procedure ApplyPendingImage;
    function FetchWikiThumbUrls(const CityName: string; out OutUrls: TArray<string>): Boolean;
    function FetchWikiThumbsByTitles(const Titles: array of string; out OutUrls: TArray<string>): Boolean;
    function SlugifyCity(const City: string): string;
    function AddSigParam(const Url, Sig: string): string;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  Form1: TForm1;

implementation

{$R *.fmx}

constructor TForm1.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Root layout (padding and vertical stacking)
  if RootLayout = nil then
  begin
    // TabControl with two tabs
    TabControl := TTabControl.Create(Self);
    TabControl.Parent := Self;
    TabControl.Align := TAlignLayout.Client;
    TabControl.TabPosition := TTabPosition.Top;
    TabControl.TabHeight := 48;

    TabWeather := TTabItem.Create(TabControl);
    TabWeather.Parent := TabControl;
    TabWeather.Text := 'Weather';

    TabGallery := TTabItem.Create(TabControl);
    TabGallery.Parent := TabControl;
    TabGallery.Text := 'Gallery';

    RootLayout := TLayout.Create(Self);
    RootLayout.Parent := TabWeather;
    RootLayout.Align := TAlignLayout.Client;
    RootLayout.Margins.Rect := TRectF.Create(16, 16, 16, 16);
  end;

  // Title bar
  if TitleBar = nil then
  begin
    TitleBar := TToolBar.Create(Self);
    TitleBar.Parent := RootLayout;
    TitleBar.Align := TAlignLayout.Top;
    TitleBar.Size.Height := 56;
    if TitleLabel = nil then
    begin
      TitleLabel := TLabel.Create(Self);
      TitleLabel.Parent := TitleBar;
      TitleLabel.Align := TAlignLayout.Contents;
      TitleLabel.Text := 'Weather';
      TitleLabel.StyledSettings := [];
    end;
  end;

  // Progress bar
  if FProgressBar = nil then
  begin
    FProgressBar := TProgressBar.Create(Self);
    FProgressBar.Parent := RootLayout;
    FProgressBar.Align := TAlignLayout.Top;
    FProgressBar.Margins.Rect := TRectF.Create(0, 12, 0, 12);
    FProgressBar.Min := 0;
    FProgressBar.Max := 100;
    FProgressBar.Value := 0;
    FProgressBar.Visible := False;
  end;

  // Location inputs group
  if LocationLayout = nil then
  begin
    LocationLayout := TLayout.Create(Self);
    LocationLayout.Parent := RootLayout;
    LocationLayout.Align := TAlignLayout.Top;
    LocationLayout.Margins.Rect := TRectF.Create(0, 0, 0, 0);
    LocationLayout.Height := 160;

    if ComboCity = nil then
    begin
      ComboCity := TComboBox.Create(Self);
      ComboCity.Parent := LocationLayout;
      ComboCity.Align := TAlignLayout.Top;
      ComboCity.Margins.Rect := TRectF.Create(0, 0, 0, 8);
      ComboCity.Width := RootLayout.Width;
      ComboCity.Items.Add('Berlin');
      ComboCity.Items.Add('London');
      ComboCity.Items.Add('New York');
      ComboCity.Items.Add('Tokyo');
      ComboCity.Items.Add('Sydney');
      ComboCity.ItemIndex := 0;
      ComboCity.OnChange := ComboCityChange;
      ComboCity.OnClosePopup := ComboCityCloseUp;
    end
    else
      ComboCity.Parent := LocationLayout;

    if EditLat = nil then
    begin
      EditLat := TEdit.Create(Self);
      EditLat.Parent := LocationLayout;
      EditLat.Align := TAlignLayout.Top;
      EditLat.Margins.Rect := TRectF.Create(0, 0, 0, 8);
      EditLat.TextPrompt := 'Latitude';
    end
    else
      EditLat.Parent := LocationLayout;

    if EditLon = nil then
    begin
      EditLon := TEdit.Create(Self);
      EditLon.Parent := LocationLayout;
      EditLon.Align := TAlignLayout.Top;
      EditLon.Margins.Rect := TRectF.Create(0, 0, 0, 0);
      EditLon.TextPrompt := 'Longitude';
    end
    else
      EditLon.Parent := LocationLayout;
  end;

  // Actions layout (buttons)
  if ActionsLayout = nil then
  begin
    ActionsLayout := TLayout.Create(Self);
    ActionsLayout.Parent := RootLayout;
    ActionsLayout.Align := TAlignLayout.Top;
    ActionsLayout.Height := 48;
    ActionsLayout.Margins.Rect := TRectF.Create(0, 12, 0, 0);
  end;

  // No refresh button; selection triggers refresh

  // Default to Berlin coordinates
  if (EditLat.Text = '') and (EditLon.Text = '') then
  begin
    EditLat.Text := '52.52';
    EditLon.Text := '13.41';
  end;


  // Readings layout
  if ReadingsLayout = nil then
  begin
    ReadingsLayout := TLayout.Create(Self);
    ReadingsLayout.Parent := RootLayout;
    ReadingsLayout.Align := TAlignLayout.Top;
    ReadingsLayout.Height := 72;
    ReadingsLayout.Margins.Rect := TRectF.Create(0, 12, 0, 0);
  end;

  if Assigned(LabelTemperature) then
  begin
    LabelTemperature.Parent := ReadingsLayout;
    LabelTemperature.Align := TAlignLayout.Top;
    LabelTemperature.Margins.Rect := TRectF.Create(0, 0, 0, 4);
  end;

  if Assigned(LabelWindSpeed) then
  begin
    LabelWindSpeed.Parent := ReadingsLayout;
    LabelWindSpeed.Align := TAlignLayout.Top;
  end;

  // Gallery page scrollable strip
  if GalleryScrollBox = nil then
  begin
    GalleryScrollBox := TScrollBox.Create(Self);
    GalleryScrollBox.Parent := TabGallery;
    GalleryScrollBox.Align := TAlignLayout.Client;
    GalleryScrollBox.ShowScrollBars := True;
    GalleryScrollBox.HitTest := True;
    GalleryScrollBox.Touch.InteractiveGestures := [TInteractiveGesture.Pan, TInteractiveGesture.Zoom];
  end;

  // Create 4 image placeholders
  var i: Integer;
  for i := 0 to 3 do
  begin
    if GalleryImages[i] = nil then
    begin
      GalleryImages[i] := TImage.Create(Self);
      GalleryImages[i].Parent := GalleryScrollBox;
      GalleryImages[i].Align := TAlignLayout.Top;
      GalleryImages[i].Height := 180;
      GalleryImages[i].WrapMode := TImageWrapMode.Fit;
      GalleryImages[i].Bitmap.Clear(TAlphaColorRec.Lightslategrey);
      GalleryImages[i].Margins.Rect := TRectF.Create(0, 0, 0, 4);
    end;

    if GalleryCaptions[i] = nil then
    begin
      GalleryCaptions[i] := TLabel.Create(Self);
      GalleryCaptions[i].Parent := GalleryScrollBox;
      GalleryCaptions[i].Align := TAlignLayout.Top;
      GalleryCaptions[i].Height := 24;
      GalleryCaptions[i].Text := '';
      GalleryCaptions[i].TextSettings.HorzAlign := TTextAlign.Center;
      GalleryCaptions[i].Margins.Rect := TRectF.Create(0, 0, 0, 12);
    end;
  end;

  // Trigger initial gallery load for default city (after images exist)
  LoadCityImages('Berlin');
end;

function TForm1.FetchWikiThumbUrls(const CityName: string; out OutUrls: TArray<string>): Boolean;
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
  JsonText: string;
  Root: TJSONValue;
  Query: string;
  Items: TJSONArray;
  I: Integer;
begin
  SetLength(OutUrls, 0);
  Result := False;
  Query := 'https://en.wikipedia.org/w/api.php?action=query&format=json&prop=pageimages|pageterms&generator=prefixsearch&gpssearch=' +
           TNetEncoding.URL.Encode(CityName) + '&gpslimit=4&pithumbsize=800&redirects=1&pilicense=any';
  Client := THTTPClient.Create;
  try
    Client.HandleRedirects := True;
    Client.UserAgent := 'AI_FMX_TEST1/1.0 (+https://example.local)';
    try
      Resp := Client.Get(Query);
      if Resp.StatusCode = 200 then
      begin
        JsonText := Resp.ContentAsString;
        Root := TJSONObject.ParseJSONValue(JsonText);
        try
          if (Root <> nil) and (Root is TJSONObject) then
          begin
            // Navigate query.pages (object of pageid->page)
            var QueryObj := TJSONObject(Root).GetValue('query') as TJSONObject;
            if QueryObj <> nil then
            begin
              var Pages := QueryObj.GetValue('pages') as TJSONObject;
              if Pages <> nil then
              begin
                // Collect up to 4 thumbnail URLs
                SetLength(OutUrls, 0);
                for I := 0 to Pages.Count - 1 do
                begin
                  var PageObj := Pages.Pairs[I].JsonValue as TJSONObject;
                  var ThumbObj := PageObj.GetValue('thumbnail') as TJSONObject;
                  if (ThumbObj <> nil) and (ThumbObj.GetValue('source') <> nil) then
                  begin
                    OutUrls := OutUrls + [ThumbObj.GetValue('source').Value];
                    if Length(OutUrls) = 4 then Break;
                  end;
                end;
                Result := Length(OutUrls) >= 1;
              end;
            end;
          end;
        finally
          Root.Free;
        end;
      end;
    except
      // ignore wiki failures; fallback happens in caller
    end;
  finally
    Client.Free;
  end;
end;

function TForm1.FetchWikiThumbsByTitles(const Titles: array of string; out OutUrls: TArray<string>): Boolean;
var
  Client: THTTPClient;
  Resp: IHTTPResponse;
  JsonText, TitlesParam: string;
  Root: TJSONValue;
  I: Integer;
begin
  SetLength(OutUrls, 0);
  Result := False;
  TitlesParam := '';
  for I := Low(Titles) to High(Titles) do
  begin
    if TitlesParam <> '' then TitlesParam := TitlesParam + '|';
    TitlesParam := TitlesParam + TNetEncoding.URL.Encode(Titles[I]);
  end;

  Client := THTTPClient.Create;
  try
    Client.HandleRedirects := True;
    Client.UserAgent := 'AI_FMX_TEST1/1.0 (+https://example.local)';
    try
      Resp := Client.Get('https://en.wikipedia.org/w/api.php?action=query&format=json&prop=pageimages&titles=' + TitlesParam + '&pithumbsize=800&redirects=1&piprop=thumbnail|name&pilicense=any');
      if Resp.StatusCode = 200 then
      begin
        JsonText := Resp.ContentAsString;
        Root := TJSONObject.ParseJSONValue(JsonText);
        try
          if (Root <> nil) and (Root is TJSONObject) then
          begin
            var QueryObj := TJSONObject(Root).GetValue('query') as TJSONObject;
            if QueryObj <> nil then
            begin
              var Pages := QueryObj.GetValue('pages') as TJSONObject;
              if Pages <> nil then
              begin
                for I := 0 to Pages.Count - 1 do
                begin
                  var PageObj := Pages.Pairs[I].JsonValue as TJSONObject;
                  var ThumbObj := PageObj.GetValue('thumbnail') as TJSONObject;
                  if (ThumbObj <> nil) and (ThumbObj.GetValue('source') <> nil) then
                    OutUrls := OutUrls + [ThumbObj.GetValue('source').Value];
                end;
                Result := Length(OutUrls) > 0;
              end;
            end;
          end;
        finally
          Root.Free;
        end;
      end;
    except
      // swallow
    end;
  finally
    Client.Free;
  end;
end;

procedure TForm1.RefreshWeather;
var
  LatInput, LonInput: string;
begin
  // Capture UI values on the main thread
  if Assigned(EditLat) then LatInput := EditLat.Text else LatInput := '52.52';
  if Assigned(EditLon) then LonInput := EditLon.Text else LonInput := '13.41';

  StartProgress;
  TTask.Run(
    procedure
    var
      Client: THTTPClient;
      JsonText: string;
      Root: TJSONValue;
      RootObj, Current: TJSONObject;
      CurrentVal: TJSONValue;
      Temperature, WindSpeed: Double;
      TemperatureStr, WindSpeedStr: string;
      Fmt: TFormatSettings;
      OkT, OkW: Boolean;
      i: Integer;
      Url, NLat, NLon: string;
      CoordOk: Boolean;
      DLat, DLon: Double;
    begin
      Fmt := TFormatSettings.Create;
      Fmt.DecimalSeparator := '.';

      // Normalize and validate coordinates
      NLat := StringReplace(Trim(LatInput), ',', '.', [rfReplaceAll]);
      NLon := StringReplace(Trim(LonInput), ',', '.', [rfReplaceAll]);
      CoordOk := TryStrToFloat(NLat, DLat, Fmt) and TryStrToFloat(NLon, DLon, Fmt);

      if CoordOk then
        Url := Format('https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current_weather=true', [NLat, NLon])
      else
        Url := '';

      Client := THTTPClient.Create;
      try
        Client.OnReceiveData := HTTPReceiveData;
        try
          for i := 1 to 20 do
          begin
            FPendingProgress := i * 2.0; // up to 40%
            TThread.Synchronize(nil, UpdateProgress);
            TThread.Sleep(50);
          end;
          if Url <> '' then
          begin
            JsonText := Client.Get(Url).ContentAsString;
            FPendingProgress := 60;
            TThread.Synchronize(nil, UpdateProgress);
          end
          else
            JsonText := '';
        except
          JsonText := '';
        end;

        if JsonText <> '' then
        begin
          Root := TJSONObject.ParseJSONValue(JsonText);
          try
            if (Root <> nil) and (Root is TJSONObject) then
            begin
              RootObj := TJSONObject(Root);
              CurrentVal := RootObj.GetValue('current_weather');
              if (CurrentVal <> nil) and (CurrentVal is TJSONObject) then
              begin
                Current := TJSONObject(CurrentVal);
                TemperatureStr := '';
                WindSpeedStr := '';
                if Current.GetValue('temperature') <> nil then
                  TemperatureStr := Current.GetValue('temperature').Value;
                if Current.GetValue('windspeed') <> nil then
                  WindSpeedStr := Current.GetValue('windspeed').Value;

                OkT := TryStrToFloat(TemperatureStr, Temperature, Fmt);
                OkW := TryStrToFloat(WindSpeedStr, WindSpeed, Fmt);

                if OkT and OkW then
                begin
                  FPendingTemperature := Temperature;
                  FPendingWindSpeed := WindSpeed;
                  TThread.Synchronize(nil, DoUpdateLabels);
                end
                else
                  TThread.Synchronize(nil, ShowUnavailable);
              end
              else
              begin
                TThread.Synchronize(nil, ShowUnavailable);
              end;
            end
            else
            begin
              TThread.Synchronize(nil, ShowError);
            end;
          finally
            Root.Free;
          end;
        end
        else
        begin
          TThread.Synchronize(nil, ShowError);
        end;
      finally
        for i := Trunc(FPendingProgress) to 100 do
        begin
          FPendingProgress := i;
          TThread.Synchronize(nil, UpdateProgress);
          TThread.Sleep(10);
        end;
        TThread.Synchronize(nil, FinishProgress);
        Client.Free;
      end;
    end);
end;

procedure TForm1.UpdateLabels(const TemperatureC, WindSpeed: Double);
begin
  LabelTemperature.Text := Format('Temperature: %.1f °C', [TemperatureC]);
  LabelWindSpeed.Text := Format('Wind: %.1f km/h', [WindSpeed]);
end;



procedure TForm1.DoUpdateLabels;
begin
  UpdateLabels(FPendingTemperature, FPendingWindSpeed);
end;

procedure TForm1.ShowUnavailable;
begin
  LabelTemperature.Text := 'Temperature: unavailable';
  LabelWindSpeed.Text := 'Wind: unavailable';
end;

procedure TForm1.ShowError;
begin
  LabelTemperature.Text := 'Temperature: error';
  LabelWindSpeed.Text := 'Wind: error';
end;

procedure TForm1.ComboCityChange(Sender: TObject);
begin
  if ComboCity.ItemIndex = 0 then // Berlin
  begin
    EditLat.Text := '52.52';
    EditLon.Text := '13.41';
  end
  else if ComboCity.ItemIndex = 1 then // London
  begin
    EditLat.Text := '51.5074';
    EditLon.Text := '-0.1278';
  end
  else if ComboCity.ItemIndex = 2 then // New York
  begin
    EditLat.Text := '40.7128';
    EditLon.Text := '-74.0060';
  end
  else if ComboCity.ItemIndex = 3 then // Tokyo
  begin
    EditLat.Text := '35.6762';
    EditLon.Text := '139.6503';
  end
  else if ComboCity.ItemIndex = 4 then // Sydney
  begin
    EditLat.Text := '-33.8688';
    EditLon.Text := '151.2093';
  end;

  // Update gallery immediately on selection change
  if Assigned(ComboCity) then
    LoadCityImages(ComboCity.Items[ComboCity.ItemIndex]);
end;

procedure TForm1.ComboCityCloseUp(Sender: TObject);
begin
  RefreshWeather;
end;

procedure TForm1.UpdateProgress;
begin
  if Assigned(FProgressBar) then
    FProgressBar.Value := FPendingProgress;
end;

procedure TForm1.StartProgress;
begin
  if Assigned(FProgressBar) then
  begin
    FProgressBar.Value := 0;
    FProgressBar.Visible := True;
    FProgressBar.Enabled := True;
  end;
end;

procedure TForm1.FinishProgress;
begin
  if Assigned(FProgressBar) then
  begin
    FProgressBar.Visible := False;
    FProgressBar.Enabled := False;
  end;
end;

procedure TForm1.HTTPReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var Abort: Boolean);
var
  Percent: Single;
begin
  if AContentLength > 0 then
    Percent := (AReadCount / AContentLength) * 100
  else
    Percent := 50;
  FPendingProgress := Percent;
  TThread.Synchronize(nil, UpdateProgress);
end;

function TForm1.MakeCityImageUrl(const Term: string): string;
var
  Enc: string;
begin
  Enc := StringReplace(Term, ' ', '%20', [rfReplaceAll]);
  Enc := StringReplace(Enc, ',', '%2C', [rfReplaceAll]);
  // Use Wikimedia Commons direct search thumbnails via Special:Redirect/file for reliability
  // Fallback to Unsplash Source if redirect fails
  Result := 'https://source.unsplash.com/800x400/?' + Enc;
end;

function TForm1.SlugifyCity(const City: string): string;
var
  S: string;
begin
  S := City.Trim.ToLower;
  S := StringReplace(S, ' ', '-', [rfReplaceAll]);
  S := StringReplace(S, '''', '', [rfReplaceAll]);
  Result := S;
end;

function TForm1.AddSigParam(const Url, Sig: string): string;
begin
  if Pos('?', Url) > 0 then
    Result := Url + '&sig=' + Sig
  else
    Result := Url + '?sig=' + Sig;
end;

procedure TForm1.ApplyPendingImage;
var
  Mem: TBytesStream;
begin
  if (FPendingImageIndex >= 0) and (FPendingImageIndex <= 3) and Assigned(GalleryImages[FPendingImageIndex]) then
  begin
    Mem := TBytesStream.Create(FPendingImageData);
    try
      GalleryImages[FPendingImageIndex].Bitmap.LoadFromStream(Mem);
      if Assigned(GalleryCaptions[FPendingImageIndex]) then
        GalleryCaptions[FPendingImageIndex].Text := FPendingImageCaption;
    finally
      Mem.Free;
    end;
  end;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  showmessage('Upload');
end;

procedure TForm1.LoadCityImages(const CityName: string);
var
  Urls: array[0..3] of string;
  i: Integer;
  Client: THTTPClient;
  Mem: TMemoryStream;
  WikiUrls: TArray<string>;
begin
  Inc(FGalleryRequestId);
  // Build city-relevant image queries using Unsplash Source (no API key required)
  // Different landmark keywords to improve relevance

  // First try exact iconic titles for known cities
  if SameText(CityName, 'London') then
  begin
    if FetchWikiThumbsByTitles(['Big Ben', 'Tower Bridge', 'London Eye', 'Buckingham Palace'], WikiUrls) and (Length(WikiUrls) >= 4) then
    begin
      Urls[0] := WikiUrls[0];
      Urls[1] := WikiUrls[1];
      Urls[2] := WikiUrls[2];
      Urls[3] := WikiUrls[3];
    end
    else
      ; // fallthrough to generic logic
  end
  else if SameText(CityName, 'New York') then
  begin
    if FetchWikiThumbsByTitles(['Statue of Liberty', 'Times Square', 'Brooklyn Bridge', 'Empire State Building'], WikiUrls) and (Length(WikiUrls) >= 4) then
    begin
      Urls[0] := WikiUrls[0];
      Urls[1] := WikiUrls[1];
      Urls[2] := WikiUrls[2];
      Urls[3] := WikiUrls[3];
    end
    else
      ;
  end
  else if SameText(CityName, 'Tokyo') then
  begin
    if FetchWikiThumbsByTitles(['Tokyo Tower', 'Shibuya Crossing', 'Senso-ji', 'Tokyo Skytree'], WikiUrls) and (Length(WikiUrls) >= 4) then
      for i := 0 to 3 do Urls[i] := WikiUrls[i]
    else
      ;
  end
  else if SameText(CityName, 'Sydney') then
  begin
    if FetchWikiThumbsByTitles(['Sydney Opera House', 'Sydney Harbour Bridge', 'Bondi Beach', 'Darling Harbour'], WikiUrls) and (Length(WikiUrls) >= 4) then
      for i := 0 to 3 do Urls[i] := WikiUrls[i]
    else
      ;
  end
  else if FetchWikiThumbUrls(CityName, WikiUrls) and (Length(WikiUrls) >= 4) then
  begin
    for i := 0 to 3 do
      Urls[i] := AddSigParam(WikiUrls[i], SlugifyCity(CityName) + '-' + i.ToString);
  end
  else if SameText(CityName, 'Berlin') then
  begin
    Urls[0] := MakeCityImageUrl('Berlin skyline');
    Urls[1] := MakeCityImageUrl('Brandenburg Gate');
    Urls[2] := MakeCityImageUrl('Berlin TV Tower');
    Urls[3] := MakeCityImageUrl('Berlin street');
  end
  else if SameText(CityName, 'London') then
  begin
    Urls[0] := AddSigParam(MakeCityImageUrl('London skyline'), 'london-0');
    Urls[1] := AddSigParam(MakeCityImageUrl('Tower Bridge London'), 'london-1');
    Urls[2] := AddSigParam(MakeCityImageUrl('Westminster Big Ben London'), 'london-2');
    Urls[3] := AddSigParam(MakeCityImageUrl('London street city of london'), 'london-3');
  end
  else if SameText(CityName, 'New York') then
  begin
    Urls[0] := AddSigParam(MakeCityImageUrl('New York skyline manhattan'), 'newyork-0');
    Urls[1] := AddSigParam(MakeCityImageUrl('Times Square New York'), 'newyork-1');
    Urls[2] := AddSigParam(MakeCityImageUrl('Brooklyn Bridge New York'), 'newyork-2');
    Urls[3] := AddSigParam(MakeCityImageUrl('Central Park New York'), 'newyork-3');
  end
  else if SameText(CityName, 'Tokyo') then
  begin
    Urls[0] := MakeCityImageUrl('Tokyo skyline');
    Urls[1] := MakeCityImageUrl('Shibuya Crossing');
    Urls[2] := MakeCityImageUrl('Tokyo Tower');
    Urls[3] := MakeCityImageUrl('Asakusa Senso-ji');
  end
  else if SameText(CityName, 'Sydney') then
  begin
    Urls[0] := MakeCityImageUrl('Sydney skyline');
    Urls[1] := MakeCityImageUrl('Sydney Opera House');
    Urls[2] := MakeCityImageUrl('Sydney Harbour Bridge');
    Urls[3] := MakeCityImageUrl('Bondi Beach');
  end
  else
  begin
    // Fallback: generic city view for unknown items
    for i := 0 to 3 do
      Urls[i] := MakeCityImageUrl(CityName + ' city');
  end;

  TTask.Run(
    procedure
    var
      j: Integer;
      Resp: IHTTPResponse;
      RequestId: Integer;
    begin
      RequestId := FGalleryRequestId;
      Client := THTTPClient.Create;
      try
        Client.HandleRedirects := True;
        Client.Accept := 'image/*';
        for j := 0 to 3 do
        begin
          Mem := TMemoryStream.Create;
          try
            try
              Resp := Client.Get(Urls[j], Mem);
              if ((Resp.StatusCode >= 200) and (Resp.StatusCode < 300)) and (Mem.Size > 0) then
              begin
                Mem.Position := 0;
                SetLength(FPendingImageData, Mem.Size);
                Mem.ReadBuffer(FPendingImageData[0], Mem.Size);
                FPendingImageIndex := j;
                // Set caption to landmark or city name fallback
                if SameText(CityName, 'London') then
                begin
                  case j of
                    0: FPendingImageCaption := 'Big Ben';
                    1: FPendingImageCaption := 'Tower Bridge';
                    2: FPendingImageCaption := 'London Eye';
                    else FPendingImageCaption := 'Buckingham Palace';
                  end;
                end
                else if SameText(CityName, 'New York') then
                begin
                  case j of
                    0: FPendingImageCaption := 'Statue of Liberty';
                    1: FPendingImageCaption := 'Times Square';
                    2: FPendingImageCaption := 'Brooklyn Bridge';
                    else FPendingImageCaption := 'Empire State Building';
                  end;
                end
                else if SameText(CityName, 'Tokyo') then
                begin
                  case j of
                    0: FPendingImageCaption := 'Tokyo Tower';
                    1: FPendingImageCaption := 'Shibuya Crossing';
                    2: FPendingImageCaption := 'Sensō-ji';
                    else FPendingImageCaption := 'Tokyo Skytree';
                  end;
                end
                else if SameText(CityName, 'Sydney') then
                begin
                  case j of
                    0: FPendingImageCaption := 'Sydney Opera House';
                    1: FPendingImageCaption := 'Sydney Harbour Bridge';
                    2: FPendingImageCaption := 'Bondi Beach';
                    else FPendingImageCaption := 'Darling Harbour';
                  end;
                end
                else
                  FPendingImageCaption := CityName;
                TThread.Synchronize(nil,
                  procedure
                  begin
                    if RequestId = FGalleryRequestId then
                      ApplyPendingImage;
                  end);
              end;
            except
              // ignore individual image errors
            end;
          finally
            Mem.Free;
          end;
        end;
      finally
        Client.Free;
      end;
    end);
end;

end.
