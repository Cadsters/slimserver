# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# $Id: Player.pm,v 1.23 2004/08/25 23:24:45 dean Exp $
#
package Slim::Player::Player;
use strict;
use Slim::Player::Client;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw (string);
use Slim::Display::VFD::Animation;

our @ISA = ("Slim::Player::Client");

my @fonttable = ( ['small', 'small'],
		   		  [ undef, 'large']);

sub new {
	my $class = shift;
	my $id = shift;
	my $paddr = shift;
	my $revision = shift;
	my $client = Slim::Player::Client->new($id, $paddr);
	bless $client, $class;

	# initialize model-specific features:
	$client->revision($revision);

	return $client;
}

sub init {
	my $client = shift;
	# fire it up!
	$client->power(Slim::Utils::Prefs::clientGet($client,'power'));
	$client->startup();
                
	# start the screen saver
	Slim::Buttons::ScreenSaver::screenSaver($client);
}

# usage							float		buffer fullness as a percentage
sub usage {
	my $client = shift;
	return $client->bufferSize() ? $client->bufferFullness() / $client->bufferSize() : 0;
}

sub update {
	my $client = shift;
	my $lines = shift;
	my $nodoublesize = shift;
	
	if (Slim::Buttons::Common::param($client,'noUpdate')) {
		#mode has blocked client updates temporarily
	}	else	{ 
		$client->killAnimation();
		if (!defined($lines)) {
			Slim::Hardware::VFD::vfdUpdate($client, [Slim::Display::Display::curLines($client)]);
		} else {
			Slim::Hardware::VFD::vfdUpdate($client, $lines, $nodoublesize);
		}
	}
}	

sub isPlayer {
	return 1;
}

sub power {
	my $client = shift;
	my $on = shift;
	
	my $mode = Slim::Buttons::Common::mode($client);
	my $currOn;
	if (defined($mode)) {
		$currOn = $mode ne "off" ? 1 : 0;
	}
	
	if (!defined $on) {
		return ($currOn);
	} else {
		if (!defined($currOn) || ($currOn != $on)) {
			if ($on) {
				Slim::Buttons::Common::setMode($client, 'home');
				
				my $welcome = ($client->linesPerScreen() == 1) ? '' : Slim::Display::Display::center(Slim::Utils::Strings::string('WELCOME_TO_' . $client->model));
				my $welcome2 = ($client->linesPerScreen() == 1) ? '' : Slim::Display::Display::center(Slim::Utils::Strings::string('FREE_YOUR_MUSIC'));
				$client->showBriefly($welcome, $welcome2);
				
				# restore the saved brightness, unless its completely dark...
				my $powerOnBrightness = Slim::Utils::Prefs::clientGet($client, "powerOnBrightness");
				if ($powerOnBrightness < 1) { 
					$powerOnBrightness = 1;
				}
				Slim::Utils::Prefs::clientSet($client, "powerOnBrightness", $powerOnBrightness);
				#check if there is a sync group to restore
				Slim::Player::Sync::restoreSync($client);
				# restore volume (un-mute if necessary)
				my $vol = $client->volume();
				if($vol < 0) { 
					# un-mute volume
					$vol *= -1;
					$client->volume($vol);
				}
				Slim::Control::Command::execute($client, ["mixer", "volume", $vol]);
			} else {
				Slim::Buttons::Common::setMode($client, 'off');
			}
			# remember that we were on if we restart the server
			Slim::Utils::Prefs::clientSet($client, 'power', $on ? 1 : 0);
		}
	}
}			

sub maxVolume { return 100; }
sub minVolume {	return 0; }

sub maxTreble {	return 100; }
sub minTreble {	return 0; }

sub maxBass {	return 100; }
sub minBass {	return 0; }

sub fonts {
	my $client = shift;
	my $size = shift || $client->textSize();
	return $fonttable[$size];
}


# fade the volume up or down
# $fade = number of seconds to fade 100% (positive to fade up, negative to fade down) 
# $callback is function reference to be called when the fade is complete
my %fvolume;  # keep temporary fade volume for each client
sub fade_volume {
	my($client, $fade, $callback, $callbackargs) = @_;
	$::d_ui && msg("entering fade_volume:  fade: $fade to $fvolume{$client}\n");
	
	my $faderate = 20;  # how often do we send updated fade volume commands per second
	
	Slim::Utils::Timers::killTimers($client, \&fade_volume);
	
	my $vol = Slim::Utils::Prefs::clientGet($client, "volume");
	my $mute = Slim::Utils::Prefs::clientGet($client, "mute");
	if ($vol < 0) {
		# the volume is muted, don't fade.
		$callback && (&$callback(@$callbackargs));
		return;
	}
	
	if ($mute) {
		# Set Target (Negative indicates mute, but still saves old value)
		Slim::Utils::Prefs::clientSet($client, "volume", $vol * -1);
	}

	# on the first pass, set temporary fade volume
	if(!$fvolume{$client} && $fade > 0) {
		# fading up, start volume at 0
		$fvolume{$client} = 0;
	} elsif(!$fvolume{$client}) {
		# fading down, start volume at current volume
		$fvolume{$client} = $vol;
	}

	$fvolume{$client} += $client->maxVolume() * (1/$faderate) / $fade; # fade volume

	if ($fvolume{$client} < 0) { $fvolume{$client} = 0; };
	if ($fvolume{$client} > $vol) { $fvolume{$client} = $vol; };

	$client->volume($fvolume{$client},1); # set volume

	if ($fvolume{$client} == 0 || $fvolume{$client} == $vol) {	
		# done fading
		$::d_ui && msg("fade_volume done.  fade: $fade to $fvolume{$client} (vol: $vol)\n");
		$fvolume{$client} = 0; # reset temporary fade volume 
		$callback && (&$callback(@$callbackargs));
	} else {
		$::d_ui && msg("fade_volume - setting volume to $fvolume{$client} (originally $vol)\n");
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time()+ (1/$faderate), \&fade_volume, ($fade, $callback, $callbackargs));
	}
}

# mute or un-mute volume as necessary
# A negative volume indicates that the player is muted and should be restored 
# to the absolute value when un-muted.
sub mute {
	my $client = shift;
	
	if (!$client->isPlayer()) {
		return 1;
	}
	my $vol = Slim::Utils::Prefs::clientGet($client, "volume");
	my $mute = Slim::Utils::Prefs::clientGet($client, "mute");
	
			
	if (($vol < 0) && ($mute)) {
		# mute volume
		# todo: there is actually a hardware mute feature
		# in both decoders. Need to add Decoder::mute
		&volume($client, 0);
	} else {
		# un-mute volume
		$vol *= -1;
		&volume($client, $vol);
	}
	Slim::Utils::Prefs::clientSet($client, "volume", $vol);
	Slim::Display::Display::volumeDisplay($client);
}

sub brightness {
	my ($client,$delta, $noupdate) = @_;

	if (defined($delta) ) {
		if ($delta =~ /[\+\-]\d+/) {
			$client->currBrightness( ($client->currBrightness() + $delta) );
		} else {
			$client->currBrightness( $delta );
		}

		$client->currBrightness(0) if ($client->currBrightness() < 0);
		$client->currBrightness($client->maxBrightness()) if ($client->currBrightness() > $client->maxBrightness());
	
		if (!$noupdate) {
			my $temp1 = $client->prevline1();
			my $temp2 = $client->prevline2();
			$client->update([$temp1, $temp2], 1);
		}
	}
	
	return $client->currBrightness();
}

sub maxBrightness {
	return $Slim::Hardware::VFD::MAXBRIGHTNESS;
}

sub textSize {
	my $client = shift;
	my $newsize = shift;
	
	my $mode = Slim::Buttons::Common::mode($client);
	
	my $prefname = ($mode && $mode eq 'off') ? "offDisplaySize" : "doublesize";
	
	if (defined($newsize)) {
		return	Slim::Utils::Prefs::clientSet($client, $prefname, $newsize);
	} else {
		return	Slim::Utils::Prefs::clientGet($client, $prefname);
	}
}

# $client->textSize = 1 for LARGE text, 0 for small.
sub linesPerScreen {
	my $client = shift;
	return $client->textSize() ? 1 : 2;	
}

sub maxTextSize {
	return 1;
}

sub hasDigitalOut {
	return 0;
}
	
sub displayWidth {
	return 40;
}

sub currentSongLines {
	my $client = shift;
	my ($line1, $line2, $overlay2);

	my $overlay1 = "";

	my $playlistlen = Slim::Player::Playlist::count($client);

	if ($playlistlen < 1) {

		$line1 = string('NOW_PLAYING');
		$line2 = string('NOTHING');

	} else {

		if (Slim::Player::Source::playmode($client) eq "pause") {

			$line1 = sprintf(
				string('PAUSED')." (%d %s %d) ",
				Slim::Player::Source::currentSongIndex($client) + 1, string('OUT_OF'), $playlistlen
			);

		# for taking photos of the display, comment out the line above, and use this one instead.
		# this will cause the display to show the "Now playing" screen to show when paused.
		# $line1 = "Now playing" . sprintf " (%d %s %d) ", Slim::Player::Source::currentSongIndex($client) + 1, string('OUT_OF'), $playlistlen;

		} elsif (Slim::Player::Source::playmode($client) eq "stop") {

			$line1 = sprintf(
				string('STOPPED')." (%d %s %d) ",
				Slim::Player::Source::currentSongIndex($client) + 1, string('OUT_OF'), $playlistlen
			);

		} else {

			if (Slim::Player::Source::rate($client) != 1) {
				$line1 = string('NOW_SCANNING') . ' ' . Slim::Player::Source::rate($client) . 'x';
			} elsif (Slim::Player::Playlist::shuffle($client)) {
				$line1 = string('PLAYING_RANDOMLY');
			} else {
				$line1 = string('PLAYING');
			}
			
			if ($client->volume() < 0) {
				$line1 .= " ".string('LCMUTED')
			}

			$line1 = $line1 . sprintf(
				" (%d %s %d) ",
				Slim::Player::Source::currentSongIndex($client) + 1, string('OUT_OF'), $playlistlen
			);
		} 

		$line2 = Slim::Music::Info::standardTitle($client, Slim::Player::Playlist::song($client));
		$overlay2 = Slim::Display::Display::symbol('notesymbol');

		$line1 = $client->nowPlayingModeLines($line1);
	}

	return ($line1, $line2, $overlay1, $overlay2);
}

sub nowPlayingModeLines {
	my ($client,$line1,$overlay) = @_;

	my $fractioncomplete   = 0;
	my $playingDisplayMode = Slim::Utils::Prefs::clientGet($client, "playingDisplayMode");

	Slim::Buttons::Common::param(
		$client,
		'animateTop',
		(Slim::Player::Source::playmode($client) ne "stop") ? $playingDisplayMode : 0
	);

	unless (defined $playingDisplayMode) {
		$playingDisplayMode = 1;
	};

	# check if we're streaming...
	if (Slim::Music::Info::isHTTPURL(Slim::Player::Playlist::song($client)) &&
	   !($playingDisplayMode == 6)) {

		# no progress bar, remaining time is meaningless
		$playingDisplayMode = ($playingDisplayMode % 3) ? 1 : 0;

	} else {
		$fractioncomplete = Slim::Player::Source::progress($client);
	}

	my $songtime = " " . Slim::Player::Source::textSongTime($client, $playingDisplayMode);

	my $leftLength = $client->measureText($line1, 1);

	if ( $playingDisplayMode == 6) {
		if (!Slim::Utils::Prefs::clientGet($client,'showbufferfullness')) {
			$playingDisplayMode = 1; #sanity check.  revert to showing nothign is showbufferfullnes has been turned off.
		} else {
			# show both the usage bar and numerical usage
			$fractioncomplete = $client->usage();
			my $usageLine = int($fractioncomplete * 100 + 0.5)."%";
			my $usageLineLength = $client->measureText($usageLine,1);
			
			my $barlen = $client->displayWidth()  - $leftLength - $usageLineLength;
			my $bar    = $client->progressBar($barlen, $fractioncomplete);
	
			$overlay = $bar . " " . $usageLine;
		}
	}
	
	if ($playingDisplayMode == 1 || $playingDisplayMode == 2) {
		$overlay = $songtime;

	} elsif ($playingDisplayMode == 3) {

		# just show the bar
		my $barlen = $client->displayWidth() - $leftLength;
		my $bar    = $client->progressBar($barlen, $fractioncomplete);

		$overlay = $bar;

	} elsif ($playingDisplayMode == 4 || $playingDisplayMode == 5) {

		# show both the bar and the time
		my $barlen = $client->displayWidth() - $leftLength - $client->measureText($songtime, 1);

		my $bar    = $client->progressBar($barlen, $fractioncomplete);

		$overlay = $bar . $songtime;
	}

	$line1 .= Slim::Display::Display::symbol('right') . $overlay if (defined($overlay));
	return $line1;
}

sub measureText {
	my $client = shift;
	my $text = shift;
	my $line = shift;
	
	return Slim::Display::Display::lineLength($text);
}

sub animating {
	Slim::Display::VFD::Animation::animating(@_);
}

sub killAnimation {
	Slim::Display::VFD::Animation::killAnimation(@_);
}

sub endAnimation {
	Slim::Display::VFD::Animation::endAnimation(@_);
}

sub showBriefly {
	Slim::Display::VFD::Animation::showBriefly(@_);
}

sub pushLeft {
	Slim::Display::VFD::Animation::pushLeft(@_);
}

sub pushRight {
	Slim::Display::VFD::Animation::pushRight(@_);
}

sub doEasterEgg {
	Slim::Display::VFD::Animation::doEasterEgg(@_);
}

sub bumpLeft {
	Slim::Display::VFD::Animation::bumpLeft(@_);
}

sub bumpRight {
	Slim::Display::VFD::Animation::bumpRight(@_);
}

sub bumpUp {
	Slim::Display::VFD::Animation::bumpUp(@_);
}

sub bumpDown {
	Slim::Display::VFD::Animation::bumpDown(@_);
}

sub scrollBottom {
	Slim::Display::VFD::Animation::scrollBottom(@_);
}
	
sub renderOverlay {
	my $client = shift;
	my $line1 = shift;
	my $line2 = shift;
	my $overlay1 = shift;
	my $overlay2 = shift;
	return Slim::Hardware::VFD::renderOverlay($line1, $line2, $overlay1, $overlay2);
}

# Draws a slider bar, bidirectional or single direction is possible.
# $value should be pre-processed to be from 0-100
# $midpoint specifies the position of the divider from 0-100 (use 0 for progressBar)
# returns a +/- balance/bass/treble bar text AND sets up custom characters if necessary
# range 0 to 100, 50 is middle.
sub sliderBar {
	my ($client,$width,$value,$midpoint,$fullstep) = @_;
	$midpoint = 0 unless defined $midpoint;
	if ($width == 0) {
		return "";
	}
	
	my $charwidth = 5;

	if ($value < 0) {
		$value = 0;
	}
	
	if ($value > 100) {
		$value = 100;
	}
	
	my $chart = "";
	
	my $totaldots = $charwidth + ($width - 2) * $charwidth + $charwidth;

	# felix mueller discovered some rounding errors that were causing the
	# calculations to be off.  Doing it 1000 times up seems to be better.  
	# go figure.
	my $dots = int( ( ( $value * 10 ) * $totaldots) / 1000);
	my $divider = ($midpoint/100) * ($width-2);

	my $val = $value/100 * $width;
	$width = $width - 1 if $midpoint;
	
	if ($dots < 0) { $dots = 0 };
	
	if ($dots < $charwidth) {
		$chart = $midpoint ? Slim::Display::Display::symbol('leftprogress4') : Slim::Display::Display::symbol('leftprogress'.$dots);
	} else {
		$chart = $midpoint ? Slim::Display::Display::symbol('leftprogress0') : Slim::Display::Display::symbol('leftprogress4');
	}
	
	$dots -= $charwidth;
			
	if ($midpoint) {
		for (my $i = 1; $i < $divider; $i++) {
			if ($dots <= 0) {
				$chart .= Slim::Display::Display::symbol('solidblock');
			} else {
				$chart .= Slim::Display::Display::symbol('middleprogress0');
			}
			$dots -= $charwidth;
		}
		if ($value < $midpoint) {
			$chart .= Slim::Display::Display::symbol('solidblock');
			$dots -= $charwidth;
		} else {
			$chart .= Slim::Display::Display::symbol('leftmark');
			$dots -= $charwidth;
		}
	}
	for (my $i = $divider + 1; $i < ($width - 1); $i++) {
		if ($midpoint && $i == $divider + 1) {
			if ($value > $midpoint) {
				$chart .= Slim::Display::Display::symbol('solidblock');
			} else {
				$chart .= Slim::Display::Display::symbol('rightmark');
			}
			$dots -= $charwidth;
		}
		if ($dots <= 0) {
			$chart .= Slim::Display::Display::symbol('middleprogress0');
		} elsif ($dots < $charwidth && !$fullstep) {
			$chart .= Slim::Display::Display::symbol('middleprogress'.$dots);
		} else {
			$chart .= Slim::Display::Display::symbol('solidblock');
		}
		$dots -= $charwidth;
	}
		
	if ($dots <= 0) {
		$chart .= Slim::Display::Display::symbol('rightprogress0');
	} elsif ($dots < $charwidth && !$fullstep) {
		$chart .= Slim::Display::Display::symbol('rightprogress'.$dots);
	} else {
		$chart .= Slim::Display::Display::symbol('rightprogress4');
	}
	
	return $chart;
}

# returns progress bar text
sub progressBar {
	return sliderBar(shift,shift,(shift)*100,0);
}

sub balanceBar {
	return sliderBar(shift,shift,shift,50);
}






1;

